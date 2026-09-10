#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "fileutils"
require "optparse"
require "time"
require "yaml"

LANGUAGES = %w[zh en jp].freeze

options = { dry_run: false }

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} [draft.md] [zh|en|jp] [options]"
  opts.separator "Select one file directly in _drafts/ and move it to _posts/<language>/."
  opts.on("-n", "--dry-run", "Show what would be moved without changing files") do
    options[:dry_run] = true
  end
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit
  end
end

parser.parse!
abort parser.to_s if ARGV.length > 2

site_root = File.expand_path("..", __dir__)
draft_root = File.join(site_root, "_drafts")
abort "No draft directory: #{draft_root}" unless Dir.exist?(draft_root)

drafts = Dir.glob(File.join(draft_root, "*")).select do |path|
  File.file?(path) && !File.symlink?(path) && %w[.md .markdown].include?(File.extname(path).downcase)
end.sort
abort "No Markdown drafts directly in #{draft_root}" if drafts.empty?

draft_argument, language = ARGV
if draft_argument
  candidate = if File.basename(draft_argument) == draft_argument
                File.join(draft_root, draft_argument)
              else
                File.expand_path(draft_argument)
              end
  source = drafts.find { |path| path == candidate }
  abort "Draft must be a Markdown file directly in #{draft_root}: #{draft_argument}" unless source
else
  abort "Specify a draft filename as the first argument." unless $stdin.tty?
  puts "Choose one draft:"
  drafts.each_with_index { |path, index| puts "  #{index + 1}) #{File.basename(path)}" }
  print "> "
  answer = $stdin.gets&.strip
  index = answer.to_i - 1 if answer&.match?(/\A[1-9]\d*\z/)
  abort "Invalid draft selection." unless index && index < drafts.length
  source = drafts[index]
end

if language.nil?
  unless $stdin.tty?
    warn parser
    abort "Choose one language: #{LANGUAGES.join(', ')}"
  end

  puts "Choose destination language (_posts/<language>/):"
  LANGUAGES.each_with_index { |item, index| puts "  #{index + 1}) #{item}" }
  print "> "

  answer = $stdin.gets&.strip
  language = if answer&.match?(/\A[1-3]\z/)
               LANGUAGES[answer.to_i - 1]
             else
               answer&.downcase
             end
end

unless LANGUAGES.include?(language)
  warn parser
  abort "Invalid language: #{language.inspect}"
end

post_root = File.join(site_root, "_posts", language)

def front_matter(content)
  match = content.match(/\A---\s*\r?\n(.*?)\r?\n---\s*(?:\r?\n|\z)/m)
  return unless match

  metadata = YAML.safe_load(
    match[1],
    permitted_classes: [Date, DateTime, Time],
    aliases: true
  )
  metadata if metadata.is_a?(Hash)
rescue Psych::Exception => e
  warn "  invalid YAML: #{e.message.lines.first.strip}"
  nil
end

def timestamp(value)
  return value.to_time if value.is_a?(DateTime)
  return value if value.is_a?(Time)

  # A date without a clock time is intentionally not publishable.
  return unless value.is_a?(String) && value.match?(/\b\d{1,2}:\d{2}(?::\d{2})?\b/)

  Time.parse(value)
rescue ArgumentError
  nil
end

filename = File.basename(source)
metadata = front_matter(File.read(source, encoding: "UTF-8"))
abort "No valid YAML front matter: #{filename}" unless metadata
abort "Draft has published: false: #{filename}" if metadata["published"] == false

publish_at = timestamp(metadata["date"])
abort "date must contain a valid date and time: #{filename}" unless publish_at

extension = File.extname(filename)
basename = File.basename(filename, extension).sub(/\A\d{4}-\d{2}-\d{2}-/, "")
post_name = "#{publish_at.strftime('%Y-%m-%d')}-#{basename}#{extension}"
destination = File.join(post_root, post_name)
abort "Destination already exists: #{destination}" if File.exist?(destination) || File.symlink?(destination)

unless options[:dry_run]
  FileUtils.mkdir_p(post_root)
  FileUtils.mv(source, destination)
end

puts "[#{options[:dry_run] ? 'would move' : 'moved'}] #{source} -> #{destination}"
