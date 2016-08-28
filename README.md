# RediXML

Downloads zip files containing XML of news stories and stores them in a Redis list, which can be available for any web app to consume.
 
## Installation

Get the code:

```
git clone https://github.com/cmelgarejo/RediXML.git
```

And then execute:

    $ bundle

## Requirements

* Ruby 2.x.x
* Redis

## Usage


```
ruby redi_xml.rb [options]
```

Where `[options]` are:

```
'-r redis://URL' or '--redis redis://URL' #Redis instance URL to be connected
'-u URL' or '--url URL' #URL to parse and get .zip files
'-p path/to/zip/files' or '--path path/to/zip/files' #Where to save the zip files
```

The script will download the zip list from the given URL and then parse the entries, processing each one.
It's idempotent enough to be run several instances and it'll use Redis to store the completeness of each zip file individually

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/cmelgarejo/RediXML. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

This little script is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).