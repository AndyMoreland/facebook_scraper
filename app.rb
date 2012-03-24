require 'rubygems'
require 'sinatra'
require 'json'
require 'yaml'
require 'mongoid'
require 'cgi'
require 'resque'


Mongoid.configure do |config|
  config.master = Mongo::Connection.new.db("facebook_scraper_2")
end


module FacebookAPI
  @@base_url = "https://graph.facebook.com"
  ALL_PERMISSIONS =
"offline_access,user_about_me,friends_about_me,user_activities,friends_activities,user_birthday,friends_birthday,user_education_history,friends_education_history,user_groups,friends_groups,user_hometown,friends_hometown,user_interests,friends_interests,user_likes,friends_likes,user_location,friends_location,user_relationships,friends_relationships,user_relationship_details,friends_relationship_details,user_religion_politics,friends_religion_politics,user_website,friends_website,user_work_history,friends_work_history" 
  def self.get_request url, options_hash = {}
    argument_string = "#{@@base_url}/#{url}"
    argument_string = argument_string + "?access_token=#{options_hash[:api_key]}" if options_hash[:api_key]
    `echo "#{argument_string}" >> foo.txt`
    str = `curl -s "#{argument_string}"`
    `echo "#{str}" >> log.txt`
    str
  end

  def self.get_object id, options_hash = {}
   self.get_request id, options_hash
  end

  def self.get_connection id, connection, options_hash = {}
   self.get_request "#{id}/#{connection}", options_hash
  end

  def self.fetch_access_key code #WHY WON'T I WOKR!?
    url =  "https://graph.facebook.com/oauth/access_token?client_id=112631612153148&redirect_uri=http://facebook.andymoreland.com:4567/response/&client_secret=368da99f402c9055cb2fd8e0b6b755ce&code=#{code}"
    argument_string = "curl -s \"#{url}\""
    str = `#{argument_string}`.scan(/access_token=(.*)/)[0][0]
    `echo "#{argument_string}" >> foo3.txt`
    `echo #{str} >> foo2.txt`
    str
  end
end

##################

module PersonMethods
  def movies(id, api_key)
    begin
      str = FacebookAPI.get_connection(id, "movies", :api_key => api_key)
      h = JSON.parse(str)["data"]
    rescue
      return nil
    end
  end

  def books(id, api_key)
    begin
      str = FacebookAPI.get_connection(id, "books", :api_key => api_key)
      h = JSON.parse(str)["data"]
    rescue
      return nil
    end
  end

  def activities(id, api_key)
    begin
    str = FacebookAPI.get_connection(id, "activities", :api_key => api_key)
    h = JSON.parse(str)["data"]
    rescue
      return nil
    end
  end

  def likes(id, api_key)
    begin
    str = FacebookAPI.get_connection(id, "likes", :api_key => api_key)
    h = JSON.parse(str)["data"]
    rescue
      return nil
    end
  end



  def add_friend(id, api_key)
    self.friends << Friend.new.build_new_person(id, api_key)
    self.save
  end
end

class Person
  include Mongoid::Document
  include Mongoid::Timestamps
  store_in :people
  embeds_many :friends

  include PersonMethods

  def build_new_person(id, api_key)
    str = FacebookAPI.get_object(id, :api_key => api_key)
    h = JSON.parse(str)
    p = self
    h.each do |k,v|
      p[k] = v
    end
    p["movies"] = movies(id, api_key)
    p["books"] = books(id, api_key)
    p["activities"] = activities(id, api_key)
    p["likes"] = likes(id, api_key)
    p["api_key"] = api_key
    p["friends"] = []

    p.save
    p
  end


end

class Friend
  include Mongoid::Document
  embedded_in :person

  include PersonMethods
  def build_new_person(id, api_key)
    str = FacebookAPI.get_object(id, :api_key => api_key)
    h = JSON.parse(str)
    p = self
    h.each do |k,v|
      p[k] = v
    end
    p["movies"] = movies(id, api_key)
    p["books"] = books(id, api_key)
    p["activities"] = activities(id, api_key)
    p["likes"] = likes(id, api_key)
    p["api_key"] = api_key
    p["friends"] = []
    p
  end

end

#############################################

class IncomingRequest
  @queue = :facebook_scrape_1
  def self.perform(code, id)
    api_key = FacebookAPI.fetch_access_key(code)
    root = Person.new.build_new_person("me", api_key) ###THIS ONLY WORKS FOR ME, NO ONE ELSE
    
    h = extract_friends_for("me", api_key)
    h.each { |friend| root.add_friend(friend["id"], api_key)}
  end
end

def redirect url
  "<script>window.location='#{url}'</script>"
end

def extract_friends_for(id, api_key)
  #Returns an array of hashes with keys id, name
  str = FacebookAPI.get_connection(id, "friends", :api_key => api_key)
  h = JSON.parse(str)["data"]
end

set :views, File.dirname(__FILE__) + '/views'
set :public, File.dirname(__FILE__) + '/public'

get '/' do
   redirect "http://www.facebook.com/dialog/oauth/?scope=#{FacebookAPI::ALL_PERMISSIONS}&client_id=112631612153148&redirect_uri=http://facebook.andymoreland.com:4567/response/"
end

get '/response/' do
  code = params["code"]
  Resque.enqueue(IncomingRequest, code, "me")
  "<center><h1>Thank you!</h1></center>"
end

get '/status/' do
  people = Person.all
  str = "<table><tr><th>Person</th><th>Friends Count</th></tr>"
  people.each do |p|
    str += "<tr><td>#{p["name"]}</td><td>#{p.friends.size}</td></tr>"
  end
  str += "</table>"
end

get '/map' do
  erb :map
end
