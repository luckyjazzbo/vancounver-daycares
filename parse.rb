require 'faraday'
require 'lightly'
require 'csv'
require 'geocoder'

$cache = Lightly.new dir: './childcare_cache', life: '365d'

class Lightly
  def [](key)
    load(key) if cached?(key)
  end

  def []=(key, value)
    save(key, value)
  end

  def del(key)
    clear(key)
  end
end

Geocoder.configure(
  timeout: 5,
  units: :km,
  cache: $cache
)

def get(url)
  $cache.get url do
    Faraday.get(url).body
  end
end

city_name = :coquitlam
city = {
  burnaby: {
    url: 'https://www.healthspace.ca/Clients/FHA/FHA_Website.nsf/CCFL-Child-List-All?OpenView&RestrictToCategory=23B11DF8A3C9C1E63649D5E3AD0748DC&count=1000&start=1',
    target_coordinates: [49.2276595, -123.0179715],
    target_name: 'central_park',
  },
  port_moody: {
    url: 'https://www.healthspace.ca/Clients/FHA/FHA_Website.nsf/CCFL-Child-List-All?OpenView&RestrictToCategory=0F12D12B4988A647E049A7DBB99B8D25&&count=1000&start=1',
    target_coordinates: [49.2779657, -122.8461655],
    target_name: 'moody_center_station',
  },
  new_westminster: {
    url: 'https://www.healthspace.ca/Clients/FHA/FHA_Website.nsf/CCFL-Child-List-All?OpenView&RestrictToCategory=704BC2C5FE08E4962CC3CC7339D9E4CB&Count=1000&start=1',
    target_coordinates: [49.2027065, -122.9064104],
    target_name: 'westminster_pier_park',
  },
  coquitlam: {
    url: 'https://www.healthspace.ca/Clients/FHA/FHA_Website.nsf/CCFL-Child-List-All?OpenView&Count=30&RestrictToCategory=1BA31309BB2C37BD77B117A0F94A5BBB&Count=1000&start=1',
    target_coordinates: [49.2749239, -122.8006107],
    target_name: 'coquitlam_central_station',
  },
}[city_name]

index_body = get city[:url]
index_pattern = /<img src="\/Clients\/FHA\/FHA_Website\.nsf\/linksquare\.gif" alt=""><a href="([^"]+)">([^<]+)<\/A><\/td><td valign="top" NOWRAP>&nbsp;([^<]+)<\/td>/
daycares = index_body.scan index_pattern

location_pattern = /<B>Facility Location:<\/B><BR>([^<]+)<\/P>/
type_pattern = /<tr><td><b>Facility Information:<\/b><\/td><\/tr>\s*<tr><td>Facility Type: (.+)<\/td><\/tr>\s*<tr><td>Service Type\(s\): (.+)<\/td>\s*<\/tr>\s*<tr><td>Capacity: (\d+)<\/td><\/tr>/
inspection_pattern = />Routine Inspection<\/a>/

daycares = daycares.map do |url, name, phone|
  url = "https://www.healthspace.ca#{url}"
  daycare_body = get url
  location = daycare_body.match(location_pattern)[1].strip
  _, facility_type, service_type, capacity = daycare_body.match(type_pattern).to_a.map(&:strip)
  num_inspections = daycare_body.scan(inspection_pattern).length

  next if service_type == '304 Family Child Care'
  next if service_type == '311 In-Home Multi-Age Child Care'
  next if service_type == '310 Multi-Age Child Care'
  next if service_type == '305 Group Child Care (School Age)'
  next if capacity.to_i <= 10

  sanitized_location = location.gsub(/,\s*.{3}\s*.{3}$/, '')
                               .gsub(/^.{1,10}\s*\-\s*/, '')
  encoded_location = Geocoder.search(sanitized_location)[0]
  if encoded_location
    distance_to_target = Geocoder::Calculations.distance_between(city[:target_coordinates], encoded_location.coordinates).round(2)
  end

  print '.'

  {
    name: name,
    phone: phone,
    location: location,
    service_type: service_type,
    capacity: capacity,
    num_inspections: num_inspections,
    coordinates: encoded_location&.coordinates,
    distance_to_target: distance_to_target,
  }
end

puts "\nFINISHED"

daycares = daycares.compact.sort_by { |daycare| daycare[:distance_to_target] || -1 }

CSV.open("./#{city_name}_childcares.csv", 'w') do |csv|
  csv << [
    'name',
    'phone',
    'location',
    'service_type',
    'capacity',
    'num_inspections',
    "distance_to_#{city[:target_name]}",
    'coordinates',
  ]
  daycares.each do |daycare|
    csv << [
      daycare[:name],
      daycare[:phone],
      daycare[:location],
      daycare[:service_type],
      daycare[:capacity],
      daycare[:num_inspections],
      daycare[:distance_to_target],
      (daycare[:coordinates] || []).map(&:to_s).join(', ')
    ]
  end
end
