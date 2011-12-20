# -*- coding: utf-8 -*-
#
# Copyright (C) 2011  Miho SUZUKI
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'thor'
require 'rainbow'
require "logaling/repository"
require "logaling/glossary"
require "logaling/external_glossary"

class Logaling::Command < Thor
  VERSION = "0.0.9"
  LOGALING_CONFIG = '.logaling'

  map '-a' => :add,
      '-d' => :delete,
      '-u' => :update,
      '-l' => :lookup,
      '-i' => :import,
      '-n' => :new,
      '-r' => :register,
      '-U' => :unregister,
      '-v' => :version

  class_option "glossary",        type: :string, aliases: "-g"
  class_option "source-language", type: :string, aliases: "-S"
  class_option "target-language", type: :string, aliases: "-T"
  class_option "logaling-home",   type: :string, aliases: "-h"

  desc 'new [PROJECT NAME] [SOURCE LANGUAGE] [TARGET LANGUAGE(optional)]', 'Create .logaling'
  method_option "no-register", type: :boolean, default: false
  def new(project_name, source_language, target_language=nil)
    unless File.exist?(LOGALING_CONFIG)
      FileUtils.mkdir_p(File.join(LOGALING_CONFIG, "glossary"))
      config = {"glossary" => project_name, "source-language" => source_language}
      config["target-language"] = target_language if target_language
      write_config(File.join(LOGALING_CONFIG, "config"), config)

      register unless options["no-register"]
      say "Successfully created #{LOGALING_CONFIG}"
    else
      say "#{LOGALING_CONFIG} already exists."
    end
  end

  desc 'import', 'Import external glossary'
  method_option "list", type: :boolean, default: false
  def import(external_glossary=nil)
    Logaling::ExternalGlossary.load
    if options["list"]
      Logaling::ExternalGlossary.list.each {|glossary| say "#{glossary.name.bright} : #{glossary.description}" }
    else
      repository.import(Logaling::ExternalGlossary.get(external_glossary))
    end
  rescue Logaling::ExternalGlossaryNotFound
    say "'#{external_glossary}' can't find in import list."
    say "Try 'loga import --list' and confirm import list."
  end

  desc 'register', 'Register .logaling'
  def register
    logaling_path = find_dotfile

    required_options = {"glossary" => "input glossary name '-g <glossary name>'"}
    config = load_config_and_merge_options(required_options)

    repository.register(logaling_path, config["glossary"])
    say "#{config['glossary']} is now registered to logaling."
  rescue Logaling::CommandFailed => e
    say e.message
    say "Try 'loga new' first."
  rescue Logaling::GlossaryAlreadyRegistered => e
    say "#{config['glossary']} is already registered."
  end

  desc 'unregister', 'Unregister .logaling'
  def unregister
    required_options = {"glossary" => "input glossary name '-g <glossary name>'"}
    config = load_config_and_merge_options(required_options)

    repository.unregister(config["glossary"])
    say "#{config['glossary']} is now unregistered."
  rescue Logaling::CommandFailed => e
    say e.message
  rescue Logaling::GlossaryNotFound => e
    say "#{config['glossary']} is not yet registered."
  end

  desc 'config [-S SOURCE LANGUAGE(optional)] [-T TARGET LANGUAGE(optional)] [--global(optional)]', 'Set config.'
  method_option "global", type: :boolean, default: false
  method_option "source-language", type: :string, aliases: "-S"
  method_option "target-language", type: :string, aliases: "-T"
  def config
    if !options['source-language'] && !options['target-language']
      say "Please input source language or target language."
      say "Try 'loga config -S en -T ja'."
    else
      if options["global"]
        config_path = File.join(LOGALING_HOME, "config")
        FileUtils.touch(config_path) unless File.exist?(config_path)
      else
        if find_dotfile
          config_path = File.join(find_dotfile, "config")
        else
          say ".logaling not found."
        end
      end

      if File.exist?(config_path)
        config = load_config(config_path)
        config = merge_options(options, config)
        write_config(config_path, config)
        say "Successfully set config."
      end
    end
  end

  desc 'add [SOURCE TERM] [TARGET TERM] [NOTE(optional)]', 'Add term to glossary.'
  def add(source_term, target_term, note='')
    glossary.add(source_term, target_term, note)
  rescue Logaling::CommandFailed, Logaling::TermError => e
    say e.message
  end

  desc 'delete [SOURCE TERM] [TARGET TERM(optional)] [--force(optional)]', 'Delete term.'
  method_option "force", type: :boolean, default: false
  def delete(source_term, target_term=nil)
    if target_term
      glossary.delete(source_term, target_term)
    else
      glossary.delete_all(source_term, options["force"])
    end
  rescue Logaling::CommandFailed, Logaling::TermError => e
    say e.message
  rescue Logaling::GlossaryNotFound => e
    say "Try 'loga new or register' first."
  end

  desc 'update [SOURCE TERM] [TARGET TERM] [NEW TARGET TERM], [NOTE(optional)]', 'Update term.'
  def update(source_term, target_term, new_target_term, note='')
    glossary.update(source_term, target_term, new_target_term, note)
  rescue Logaling::CommandFailed, Logaling::TermError => e
    say e.message
  rescue Logaling::GlossaryNotFound => e
    say "Try 'loga new or register' first."
  end

  desc 'lookup [TERM]', 'Lookup terms.'
  def lookup(source_term)
    config = load_config_and_merge_options
    repository.index
    terms = repository.lookup(source_term, config["source_language"], config["target_language"], config["glossary"])

    unless terms.empty?
      max_str_size = terms.map{|term| term[:source_term].size}.sort.last
      terms.each do |term|
        target_string = "#{term[:target_term].bright}"
        target_string <<  "\t# #{term[:note]}" unless term[:note].empty?
        if repository.glossary_counts > 1
          color = (term[:name] == config["glossary"]) ? :green : :cyan
          target_string << "\t(#{term[:name]})".color(color)
        end
        source_string = term[:source_term].split(source_term).insert(1, source_term.dup.bright).join
        printf("  %-#{max_str_size+10}s %s\n", source_string, target_string)
      end
    else
      "source-term <#{source_term}> not found"
    end
  rescue Logaling::CommandFailed, Logaling::TermError => e
    say e.message
  end

  desc 'version', 'Show version.'
  def version
    say "logaling-command version #{Logaling::Command::VERSION}"
  end

  private
  def repository
    @repository ||= Logaling::Repository.new(LOGALING_HOME)
  end

  def glossary
    if @glossary
      @glossary
    else
      required_options = {
        "glossary" => "input glossary name '-g <glossary name>'",
        "source-language" => "input source-language code '-S <source-language code>'",
        "target-language" => "input target-language code '-T <target-language code>'"
      }
      config = load_config_and_merge_options(required_options)
      @glossary = Logaling::Glossary.new(config["glossary"], config["source-language"], config["target-language"])
    end
  end

  def error(msg)
    STDERR.puts(msg)
    exit 1
  end

  def load_config_and_merge_options(required={})
    config_list ||= {}
    find_config.each{|type, path| config_list[type] = load_config(path)}
    global_config = config_list["global_config"] ? config_list["global_config"] : {}
    project_config = config_list["project_config"] ? config_list["project_config"] : {}

    config = merge_options(project_config, global_config)
    config = merge_options(options, config)

    required.each do |required_option, message|
      raise(Logaling::CommandFailed, message) unless config[required_option]
    end

    config
  end

  def merge_options(options, secondary_options)
    config ||={}
    config["glossary"] = options["glossary"] ? options["glossary"] : secondary_options["glossary"]
    config["source-language"] = options["source-language"] ? options["source-language"] : secondary_options["source-language"]
    config["target-language"] = options["target-language"] ? options["target-language"] : secondary_options["target-language"]
    config
  end

  def find_config
    config ||= {}
    config["project_config"] = File.join(find_dotfile, 'config')
    config["global_config"] = global_config_path if global_config_path
    config
  rescue Logaling::CommandFailed
    config ||= {}
    config["project_config"] = repository.config_path if repository.config_path
    config["global_config"] = global_config_path if global_config_path
    config
  end

  def load_config(config_path=nil)
    config ||= {}
    if config_path
      File.readlines(config_path).map{|l| l.chomp.split " "}.each do |option|
        key = option[0].sub(/^[\-]{2}/, "")
        value = option[1]
        config[key] = value
      end
    end
    config
  end

  def find_dotfile
    dir = Dir.pwd
    searched_path = []
    while(dir) do
      path = File.join(dir, '.logaling')
      if File.exist?(path)
        return path
      else
        if dir != "/"
          searched_path << dir
          dir = File.dirname(dir)
        else
          raise(Logaling::CommandFailed, "Can't found .logaling in #{searched_path}")
        end
      end
    end
  end

  def global_config_path
    path = File.join(LOGALING_HOME, "config")
    File.exist?(path) ? path : nil
  end

  def write_config(config_path, config)
    File.open(config_path, 'w') do |fp|
      fp.puts "--glossary #{config['glossary']}" if config['glossary']
      fp.puts "--source-language #{config['source-language']}" if config['source-language']
      fp.puts "--target-language #{config['target-language']}" if config['target-language']
    end
  end
end
