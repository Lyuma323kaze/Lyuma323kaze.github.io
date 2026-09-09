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
  opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} [zh|en|jp] [options]"
  opts.on("-n", "--dry-run", "Show what would be moved without changing files") do
    options[:dry_run] = true
  end
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit
  end
end

parser.parse!
abort parser.to_s if ARGV.length > 1

language = ARGV.first

if language.nil?
  unless $stdin.tty?
    warn parser
    abort "Choose one language: #{LANGUAGES.join(', ')}"
  end

  puts "Choose drafts to publish:"
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

site_root = File.expand_path("..", __dir__)
draft_root = File.join(site_root, "_drafts", language)
post_root = File.join(site_root, "_posts", language)

unless Dir.exist?(draft_root)
  puts "No draft directory: #{draft_root}"
  exit
end

def front_matter(content)
  match = content.match(/\A---\s*\r?\n(.*?)\r?\n---\s*(?:\r?\n|\z)/m)
  return unless match

  YAML.safe_load(
    match[1],
    permitted_classes: [Date, DateTime, Time],
    aliases: true
  ) || {}
rescue Psych::SyntaxError => e
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

drafts = Dir.glob(File.join(draft_root, "*")).select do |path|
  File.file?(path) && %w[.md .markdown].include?(File.extname(path).downcase)
end.sort

counts = Hash.new(0)

drafts.each do |source|
  counts[:scanned] += 1
  filename = File.basename(source)
  metadata = front_matter(File.read(source, encoding: "UTF-8"))

  unless metadata
    puts "[skip: no valid front matter] #{filename}"
    counts[:skipped] += 1
    next
  end

  if metadata["published"] == false
    puts "[skip: published is false] #{filename}"
    counts[:skipped] += 1
    next
  end

  publish_at = timestamp(metadata["date"])
  unless publish_at
    puts "[skip: date has no valid time] #{filename}"
    counts[:skipped] += 1
    next
  end

  extension = File.extname(filename)
  basename = File.basename(filename, extension).sub(/\A\d{4}-\d{2}-\d{2}-/, "")
  post_name = "#{publish_at.strftime('%Y-%m-%d')}-#{basename}#{extension}"
  destination = File.join(post_root, post_name)

  if File.exist?(destination)
    puts "[conflict: destination exists] #{destination}"
    counts[:conflicts] += 1
    next
  end

  action = options[:dry_run] ? "would move" : "moved"
  puts "[#{action}] #{source} -> #{destination}"

  unless options[:dry_run]
    FileUtils.mkdir_p(post_root)
    FileUtils.mv(source, destination)
  end

  counts[:moved] += 1
end

puts
puts "Language: #{language}"
puts "Scanned: #{counts[:scanned]}"
puts "#{options[:dry_run] ? 'Eligible' : 'Moved'}: #{counts[:moved]}"
puts "Skipped: #{counts[:skipped]}"
puts "Conflicts: #{counts[:conflicts]}"

exit 1 if counts[:conflicts].positive?
