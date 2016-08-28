require 'optparse'
require 'nokogiri'
require 'net/http'
require 'uri'
require 'open-uri'
require 'zip'
require 'redis'
require 'fileutils'

#Method to download our .zip files containing the news XML
def download(url, filename, save_path = 'zips/')
  Thread.new do
    thread = Thread.current
    url = URI.parse url
    begin
      Net::HTTP.new(url.host, url.port).request_get(url.path) { |response|
        length = thread[:length] = response['Content-Length'].to_i
        open(save_path + filename, 'w') { |io|
          response.read_body { |chunk|
            io.write(chunk)
            thread[:done] = (thread[:done] || 0) + chunk.length
            thread[:progress] = thread[:done].quo(length) * 100
            thread[:filename] = filename
          }
        }
      }
      print "\rDownloading: #{thread[:filename]} %.2f%%\r\n" % thread[:progress].to_f
    rescue Exception => e
      puts "=> Exception: '#{e.message}'. Skipping download."
      return
    end
    puts "Stored download as #{filename}"
  end
end

options = {}

begin
  OptionParser.new do |opts|
    opts.banner = 'Usage: ruby redi_xml.rb [options]'
    opts.on('-r', '--redis redis://URL', 'Redis URL to be connected to') { |v| options[:redis_url] = v }
    opts.on('-u', '--url URL', 'URL to parse and get .zip files') { |v| options[:url] = v }
    opts.on('-p', '--path path/to/zip/files', 'Where to save the zip files') { |v| options[:redis_url] = v }
  end.parse!
rescue => e
  puts "#{e.message}"
end

FILE_PATH = options[:path] || 'zips/'
BASE_URL = options[:url] || 'http://feed.omgili.com/5Rh5AMTrc4Pv/mainstream/posts/'
REDIS_URL = options[:redis_url] || 'redis://localhost:6379'
FileUtils.makedirs FILE_PATH
redis = Redis.new(url: REDIS_URL)
puts "Opening #{BASE_URL}"
page = Nokogiri::HTML(open(BASE_URL))
list_name = 'NEWS_XML'
process_zip_list = 'ZIPS_PROCESSING'
completed_zip_list = 'ZIPS_COMPLETED'
downloading_zip_list = 'ZIPS_DOWNLOADING'
puts "#{BASE_URL} Got it! Parsing and getting files..."
page.css('table tr td a').map { |a| a['href'] if a['href'] =~ /.zip/ }.compact.uniq.map { |file|
  file_not_exists = !File.exists?("#{FILE_PATH}#{file}")
  downloading_zip = redis.hget(downloading_zip_list, file)
  puts "Does the file #{FILE_PATH}#{file} exist?: #{file_not_exists ? 'no' : 'yes'} - It has been fully downloaded?: #{downloading_zip == '1' ? 'no' : 'yes'}"
  if downloading_zip != '0' #If there's another instance running it might get the file already, so let's skip it
    redis.hset(downloading_zip_list, file, 1)
    thread = download("#{BASE_URL}#{file}", file)
    begin
      print "\rDownloading: #{thread[:filename]} %.2f%%" % thread[:progress].to_f until thread.join 1
      redis.hset(downloading_zip_list, file, 0)
      puts 'Done!'
    rescue => e
      puts "Exception while downloading: #{e.message}"
    end
  end
  downloading_zip = redis.hget(downloading_zip_list, file) #again we check the file download status
  processing_zip = redis.hget(process_zip_list, file)
  file_processed = redis.hget(completed_zip_list, file)
  puts "Does the file #{FILE_PATH}#{file} has been processed?: #{file_processed == '0' || file_processed.nil? ? 'no' : 'yes'} - Is it in process?: #{processing_zip.nil? || processing_zip == '0' ? 'no' : 'yes'}"
  if downloading_zip == '0' && processing_zip != '1' #If the zip file hasn't been processed, let's do it!
    begin
      if file_processed != '1'
        redis.hset(process_zip_list, file, 1)
        processed_files = 0
        Zip::File.open("#{FILE_PATH}#{file}") { |zip_file|
          puts "Storing #{zip_file.size} articles"
          zip_file.each { |entry|
            #print "Storing article: #{entry.name}\r\n"
            redis.hset(entry.name, 'content', entry.get_input_stream.read) #Stores a HSET, key = XML filename, value = the article itself
            redis.lrem(list_name, 1, entry.name) #If the article exists, just remove it
            redis.lpush(list_name, entry.name) #And push it in the list
            processed_files+=1
          }
          redis.hset(process_zip_list, file, 0)
          redis.hset(completed_zip_list, file, 1)
          puts "Done processing #{processed_files} files"
        }
      end
    rescue => e
      puts "Exception: #{e.message} - Processed #{processed_files} files"
    end
  end
}