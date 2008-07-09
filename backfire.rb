require 'lib/tinder/lib/tinder'
require 'lib/backpack_api_wrapper'
require 'rubygems'
require 'active_support'    


module Backfire
  LAST_UPDATED_AT_FILE='last_updated_at'
  CONFIG_FILE='config.yml'
  @@last_updated_at = nil  
  
  mattr_accessor :exit
  
  def self.config
    @@config ||= YAML.load(File.read(CONFIG_FILE))
  end
  
  def self.backpack
    @@backpack ||= Backpack.new(config['backpack']['subdomain'], config['backpack']['token'], config['backpack']['ssl'])
  end
  
  def self.campfire
    @@campfire ||= begin
      campfire = Tinder::Campfire.new(config['campfire']['subdomain'], :ssl => config['campfire']['ssl'])
      campfire.login(config['campfire']['login'], config['campfire']['password'])
      campfire
    end
  end
  
  def self.room(id = nil)
    id ||= config['campfire']
    Tinder::Room.new(campfire, 100257)
  end
  
  def self.last_updated_at
    @@last_updated_at ||= begin
      str = File.read(LAST_UPDATED_AT_FILE) rescue nil
      (str.blank? ? nil : Time.parse(str))
    end
  end
  
  def self.is_now_updated(time)
    @@last_updated_at = time
    File.open(LAST_UPDATED_AT_FILE, 'w+') do |file|
      file.write(@@last_updated_at.to_s)
    end
    true
  rescue
    false
  end
  
  def self.was_never_updated
    File.open(LAST_UPDATED_AT_FILE, 'w+') do |file|
      file.write('')
    end
    @@last_updated_at = nil
    true
  rescue
    false
  end
  
  def self.update_campfire
    puts "*** update_campfire"
    latest_updated_at = Time.at(0)
    statuses = Status.all
    entries = JournalEntry.new_entries
    unless entries.empty? && self.last_updated_at && !(statuses.find {|s| s.updated_at >= self.last_updated_at})
      update = ''
      (entries + statuses).group_by(&:user).each do |user_array|
        user = user_array.first
        user_statuses, user_entries = user_array.last.partition {|item| item.is_a? Status}
        status = user_statuses.first
        user_entries = user_entries.sort {|a,b| b.updated_at <=> a.updated_at }
        latest_updated_at = status.updated_at if status and status.updated_at > latest_updated_at
        latest_updated_at = user_entries.first.updated_at if user_entries.first and user_entries.first.updated_at > latest_updated_at
        unless user_entries.empty? and (self.last_updated_at ? status.updated_at < self.last_updated_at : true)
          update << "\n#{user.name}: #{status.message unless user_statuses.empty?}\n"
          user_entries.each do |entry|
            update << "  * #{entry.body}\n"
          end
        end
      end
      room.paste(update) unless config['campfire']['test_mode'] == true
      puts "*** Pasted to campfire:\n"
      puts update
    end
    self.is_now_updated(latest_updated_at)
  end
  
  def self.go(interval = 20)# seconds    
    puts 'Starting backfire'
    last_run = 0
    while not exit   
      if Time.now.to_i - last_run > interval
        update_campfire
        last_run = Time.now.to_i
      end
      sleep 5
    end
  end
  
  class BackpackUser
    attr_reader :name, :id
    def initialize(ary)
      hash = Array(ary).first
      @name = hash['name'].first
      @id = hash['id'].first['content'].to_i
    end
  
    def ==(obj)
      return false unless obj.class == self.class
      return (obj.name == self.name) && (obj.id == self.id)
    end
  end

  class JournalEntry
    attr_reader :user, :body, :id, :created_at, :updated_at
  
    def initialize(hash)
      @user = BackpackUser.new(hash['user'])
      @id = hash['id'].first['content'].to_i
      @updated_at = Time.parse(hash['updated-at'].first['content'])
      @created_at = Time.parse(hash['created-at'].first['content'])
      @body = hash['body'].first
    end
  
    def self.new_entries
      entries = Backfire.backpack.list_journal_entries['journal-entry']
      if Backfire.last_updated_at
        entries = entries.reject {|e| Time.parse(e['updated-at'].first['content']) < Backfire.last_updated_at}
      end
      entries.map {|e| self.new(e)}
    end
  end

  class Status
    attr_reader :user, :message, :id, :created_at, :updated_at
  
    def initialize(hash)
      @user = BackpackUser.new(hash['user'])
      @id = hash['id'].first['content'].to_i
      @updated_at = Time.parse(hash['updated-at'].first['content'])
      @message = hash['message'].first
    end
  
    def self.all
      Backfire.backpack.list_statuses['status'].map {|status| self.new(status)}
    end
  end

  
end # module Backfire                             

trap('TERM') { puts 'Exiting...'; Backfire.exit = true }
trap('INT')  { puts 'Exiting...'; Backfire.exit = true }


Backfire.go(Backfire.config['global']['interval'])
