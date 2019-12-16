#!/usr/bin/env ruby

# <bitbar.title>SureFlap Pet Status</bitbar.title>
# <bitbar.version>v1.0.0</bitbar.version>
# <bitbar.author>Henrik Nyh</bitbar.author>
# <bitbar.author.github>henrik</bitbar.author.github>
# <bitbar.desc>Show inside/outside status of pets using a SureFlap smart cat flap or pet door.</bitbar.desc>
# <bitbar.dependencies>ruby</bitbar.dependencies>

# By Henrik Nyh <https://henrik.nyh.se> 2019-12-16 under the MIT license.
# Heavily based on the https://github.com/alextoft/sureflap PHP code by Alex Toft.
#
# Has no dependencies outside the Ruby standard library (uses Net::HTTP directly and painfully).

# NOTE: You can configure these if you like.
PETS_IN_SUMMARY = [ ]  # You can exclude e.g. indoor-only cats from the menu bar by listing only the names of outdoor cats here. (But all cats show if you click it.)
HIDE_PETS = [ ]  # You can hide cats entirely by listing their names here.

require "net/http"
require "json"
require "pp"
require "time"

auth_file = File.expand_path("~/.sureflap_auth")
unless File.exist?(auth_file)
  puts ":warning: Run: echo \"me@example.com / my_pw\" > ~/.sureflap_auth"
  exit
end

EMAIL, PASSWORD = File.read(auth_file).strip.split(" / ")
ENDPOINT = "https://app.api.surehub.io"

auth_data = { email_address: EMAIL, password: PASSWORD, device_id: "0" }

post = ->(path, data) {
  uri = URI.join(ENDPOINT, path)
  req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
  req.body = data.to_json

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  hash = JSON.parse(res.body)

  raise "HTTP error!\n#{res.code} #{res.message}\n#{hash.pretty_inspect}" unless res.code == "200"

  hash
}

get = ->(path, token:) {
  uri = URI.join(ENDPOINT, path)
  req = Net::HTTP::Get.new(uri,
    "Content-Type" => "application/json",
    "Authorization" => "Bearer #{token}",
  )

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  hash = JSON.parse(res.body)

  raise "HTTP error!\n#{res.code} #{res.message}\n#{hash.pretty_inspect}" unless res.code == "200"

  hash
}

token = post.("/api/auth/login", auth_data).dig("data", "token")

household_id = get.("/api/household", token: token).dig("data", 0, "id")

data =
  get.("/api/household/#{household_id}/pet", token: token).fetch("data").map { |pet_data|
    id = pet_data.fetch("id")
    position_data = get.("/api/pet/#{id}/position", token: token).fetch("data")

    name = pet_data.fetch("name")
    is_inside = (position_data.fetch("where") == 1)
    since = Time.parse(position_data.fetch("since"))

    [ name, [ is_inside, since ] ]
  }.to_h

overlapping_pets_in_summary = (PETS_IN_SUMMARY & data.keys) - HIDE_PETS
pets_in_summary = overlapping_pets_in_summary.any? ? overlapping_pets_in_summary : data.keys

icon = ->(is_inside) { is_inside ? ":house:" : ":deciduous_tree:" }

puts pets_in_summary.map { |name|
  is_inside, _since = data.fetch(name)
  "#{icon.(is_inside)} #{name}"
}.join("  ")

puts "---"

data.each do |name, (is_inside, since)|
  next if HIDE_PETS.include?(name)

  puts "#{icon.(is_inside)} #{name} is #{is_inside ? "inside" : "outside"} since #{since.strftime("%Y-%m-%d at %H:%M")}."
end
