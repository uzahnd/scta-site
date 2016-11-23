# Sinatra example
#
# Call as http://localhost:4567/sparql?query=uri,
# where `uri` is the URI of a SPARQL query, or
# a URI-escaped SPARQL query, for example:
#   http://localhost:4567/?query=SELECT%20?s%20?p%20?o%20WHERE%20%7B?s%20?p%20?o%7D
require 'sinatra'
require 'bundler/setup'
require 'rdf'
require 'sparql'
require 'sinatra/sparql'
require 'uri'
require 'sparql/client'
require 'rdf/ntriples'
require 'cgi'
require 'equivalent-xml'
require 'open-uri'
require 'httparty'
require 'json'
require 'lbp'


if ENV['development']
  require 'pry'
end


require_relative 'lib/queries'
require_relative 'lib/custom_functions'
require_relative 'lib/ranges'
require_relative 'lib/manifests'
require_relative 'lib/collections'
require_relative 'lib/notifications'

configure do
  set :protection, except: [:frame_options]
  set :root, File.dirname(__FILE__)

  # this added in attempt to "forbidden" response when clicking on links
  set :protection, :except => :ip_spoofing
  set :protection, :except => :json
end

prefixes = "
          PREFIX owl: <http://www.w3.org/2002/07/owl#>
          PREFIX dbpedia: <http://dbpedia.org/ontology/>
          PREFIX dcterms: <http://purl.org/dc/terms/>
          PREFIX dc: <http://purl.org/dc/elements/1.1/>
          PREFIX sctap: <http://scta.info/property/>
          PREFIX sctar: <http://scta.info/resource/>
          PREFIX sctat: <http://scta.info/text/>
          PREFIX role: <http://www.loc.gov/loc.terms/relators/>
          PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
          PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
          PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
          "

def query_display_simple(query)
  query_obj = Lbp::Query.new()
  result = query_obj.query(query)
  #result = rdf_query(query)
  result.each_solution do |solution|
  puts solution.inspect
  end
end

def URLConvert (url)
  url_hash = {}
  if url.class.to_s == "RDF::Node"
    url_hash[:url_label] = url.to_s
    url_hash[:url_base] = url.to_s
    url_hash[:url_link] = url.to_s
  elsif url.to_s.include? 'http://scta.info'
    url_hash[:url_label] = url.parent.to_s
    url_hash[:url_base] = url.to_s.gsub(url.parent.to_s, '')
    url_hash[:url_link] = url.to_s.gsub('http://scta.info', '')
  elsif url.qname
    url_hash[:url_label] = url.qname[0].to_s + ":"
    url_hash[:url_base] = url.qname[1].to_s
    url_hash[:url_link] = url.to_s
  else
    url_hash[:url_label] = url.parent.to_s
    url_hash[:url_base] = url.to_s.gsub(url.parent.to_s, '')
    url_hash[:url_link] = url.to_s
  end
  return url_hash
end

# root route
get '/' do
  quotationquery = "#{prefixes}

          SELECT count(?s) {
            ?s a <http://scta.info/resource/quotation> .
          }
          "
  quotesquery = "#{prefixes}

          SELECT count(distinct ?quotes) {
            ?s sctap:quotes ?quotes .
          }
          "
  itemquery = "#{prefixes}

          SELECT count(distinct ?item) {
            ?item <http://scta.info/property/structureType> <http://scta.info/resource/structureItem> .
          }
          "
  commentaryquery = "#{prefixes}

          SELECT count(distinct ?com) {
            ?com <http://scta.info/property/expressionType> <http://scta.info/resource/commentary> .
          }
          "
  namequery = "#{prefixes}

          SELECT count(distinct ?name) {
            ?name a <http://scta.info/resource/person> .
          }
          "
  workquery = "#{prefixes}

          SELECT count(distinct ?work) {
            ?work a <http://scta.info/resource/work> .
          }
          "
  totalquery = "SELECT (count(*) as ?count) WHERE {
                       ?s ?p ?o .
                     }"
  rdf_query = Lbp::Query.new()
  @quotationcount = rdf_query.query(quotationquery).first[:".1"]
  @quotescount = rdf_query.query(quotesquery).first[:".1"]
  @itemcount = rdf_query.query(itemquery).first[:".1"]
  @commentarycount = rdf_query.query(commentaryquery).first[:".1"]
  @namecount = rdf_query.query(namequery).first[:".1"]
  @workcount = rdf_query.query(workquery).first[:".1"]
  @totalcount = rdf_query.query(totalquery).first[:count].to_i
  erb :index
end


get '/images/:filename' do |filename|
  headers( "Access-Control-Allow-Origin" => "*")
  send_file "public/#{filename}"
end
get '/logo.png' do
  send_file "public/sctalogo.png"
end

# documentation route
get '/api' do
  erb :api
end
# search route
get '/search' do
  erb :search
end

# search results route
get '/searchresults' do
  @post = "#{params[:search]}"
  @category = "#{params[:category]}"

    if @category == "questionTitle"
      #type = "item"
      predicate = "<http://scta.info/property/questionTitle>"
      query = "#{prefixes}

          SELECT ?s ?o
          {
          ?s #{predicate} ?o  .
          FILTER (REGEX(STR(?o), '#{@post}', 'i')) .
          }
          ORDER BY ?s
          "
    else
      type = @category
      predicate = "<http://purl.org/dc/elements/1.1/title>"
      query = "#{prefixes}

          SELECT ?s ?o
          {

          ?s a <http://scta.info/resource/#{type}> .
          ?s #{predicate} ?o  .
          FILTER (REGEX(STR(?o), '#{@post}', 'i')) .
          }
          ORDER BY ?s
          "
    end

  query_obj = Lbp::Query.new()
  @result = query_obj.query(query)

  erb :searchresults
end

post '/sparqlquery' do

  query = "#{params[:query]}"
  query_display_simple(query)
end

get '/iiif/collection/scta' do
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  send_file "public/scta-collection.jsonld"
end
## Depreciated; should be replaced by collection route
get '/iiif/:commentaryid/collection_old' do
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json

  # TODO; not the ideal way to do this
  # Data base should have manifest url for all manifestations
  # collection can then be built from manifesetations
  file = File.read("public/scta-collection.jsonld")
  json = JSON.parse(file)
  newcollection = json["collections"].find {|collection| collection["@id"]=="http://scta.info/iiif/collection/#{params[:commentaryid]}"}
  JSON.pretty_generate(newcollection)

end

get '/iiif/:expressionid/collection' do |expressionid|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json

  if Lbp::Resource.find(expressionid).type.short_id == "person"
    create_person_collection(expressionid)
  else
    create_collection(expressionid)
  end
end
get '/iiif/codex/:codex/manifest' do |codex|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json

  create_manifest(codex)
end
get '/iiif/custom/:shortid/manifest' do |shortid|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  create_custom_manifest(shortid)
end
get '/iiif/:expressionid/:codex/manifest' do |expressionid, codex|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  manifestation_shortid = "#{expressionid}/#{codex}"
  create_expression_manifest(manifestation_shortid)
end

# depreciated by above two routes; could be kept as a back up static or cache route
get '/iiif/:msname/manifest' do |msname|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json

  slug = msname.split("-").last
  commentary_slug = msname.split("-").first
  #msname is of the format "pp-sorb" pg-long
  send_file "public/#{msname}.jsonld"

=begin
query = "#{prefixes}

        SELECT ?commentary ?item ?order ?title ?witness ?canvas
        {
        ?commentary <http://scta.info/property/slug> '#{commentary_slug}' .
        ?commentary <http://scta.info/property/hasStructureItem> ?item .
        ?item <http://scta.info/property/hasManifestation> ?witness .
        ?item <http://scta.info/property/totalOrderNumber> ?order .
        ?item <http://purl.org/dc/elements/1.1/title> ?title .
        ?witness <http://scta.info/property/hasSlug> '#{slug}' .
        ?witness <http://scta.info/property/isOnCanvas> ?canvas
        }
        ORDER BY ?order
        "

      #@results = rdf_query(query)
      query_obj = Lbp::Query.new()
      @results = query_obj.query(query)


if @results.count > 0
    all_structures = create_range2(msname)

    structure_object = {"structures" => all_structures}
    #all_structures.to_json
    #structure_object.to_json

    json = File.read("public/#{msname}.jsonld")
    secondJsonArray = JSON.parse(json)

    newhash = secondJsonArray.merge(structure_object)

    JSON.pretty_generate(newhash)

  else
=end
end

#range test
get '/iiif/testrange/:expressionpart/:manifestationpart' do |expressionpart, manifestationpart|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  manifestationid = "#{expressionpart}/#{manifestationpart}"
  create_range2(manifestationid)
end


### SUPPLEMENT ROUTES ###

get '/iiif/:expressionpart/:manifestationpart/supplement/ranges/toc' do |expressionpart, manifestationpart|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  manifestationid = "#{expressionpart}/#{manifestationpart}"
  type = "rangelist"
  create_supplement(manifestationid, type)
end
get '/iiif/:expressionpart/:manifestationpart/notification/ranges/toc' do |expressionpart, manifestationpart|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  manifestationid = "#{expressionpart}/#{manifestationpart}"
  type = "rangelist"
  create_notification(manifestationid, type)
end
get '/iiif/:expressionpart/:manifestationpart/ranges/toc/wrapper' do |expressionpart, manifestationpart|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  manifestationid = "#{expressionpart}/#{manifestationpart}"
  all_ranges = create_range(manifestationid)
  wrapper_range = {
      "@id": "http://scta.info/iiif/#{manifestationid}/ranges/toc/wrapper",
      "@type": "sc:Range",
      "label": "#{manifestationid}",
      "viewingHint": "wrapper",
      "attribution": "Data provided by the Scholastic Commentaries and Texts Archive",
      "description": "A range list for Sentences Commentary #{manifestationid}",
      "logo": "http://scta.info/logo.png",
      "license": "https://creativecommons.org/publicdomain/zero/1.0/",
      "ranges": all_ranges
    }
  JSON.pretty_generate(wrapper_range)
end

get '/iiif/:expressionpart/:manifestationpart/supplement/service/searchwithin' do |expressionpart, manifestationpart|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  type = "searchwithin"
  manifestationid = "#{expressionpart}/#{manifestationpart}"
  create_supplement(manifestationid, type)
end
get '/iiif/:expressionpart/:manifestationpart/notification/service/searchwithin' do |expressionpart, manifestationpart|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  type = "searchwithin"
  manifestationid = "#{expressionpart}/#{manifestationpart}"
  create_notification(manifestationid, type)
end


get '/iiif/:expressionpart/:manifestationpart/supplement/layer/transcription' do |expressionpart, manifestationpart|
headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  type = "layerTranscription"
  manifestationid = "#{expressionpart}/#{manifestationpart}"
  create_supplement(manifestationid, type)
end
get '/iiif/:expressionpart/:manifestationpart/notification/layer/transcription' do |expressionpart, manifestationpart|
headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  type = "layerTranscription"
  manifestationid = "#{expressionpart}/#{manifestationpart}"
  create_notification(manifestationid, type)
end

#hard coding this for testing
get '/iiif/:expressionpart/:manifestationpart/supplement/layer/translation' do |expressionpart, manifestationpart|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  type = "layerTranslation"
  manifestationid = "#{expressionpart}/#{manifestationpart}"
  create_supplement(manifestationid, type)

end

#hard coding this for testing
get '/iiif/:expressionpart/:manifestationpart/supplement/layer/comments' do |expressionpart, manifestationpart|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  type = "layerComments"
  manifestationid = "#{expressionpart}/#{manifestationpart}"
  create_supplement(manifestationid, type)
end

#hard coding this for testing
get '/iiif/:expressionpart/:manifestationpart/layer/translation' do |expressionpart, manifestationpart|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  type = "layerTranslation"
  manifestationid = "#{expressionpart}/#{manifestationpart}"
  create_supplement(manifestationid, type)
end

#hard coding this for testing
get '/iiif/::expressionpart/:manifestationpart/layer/comments' do |expressionpart, manifestationpart|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  type = "layerComments"
  manifestationid = "#{expressionpart}/#{manifestationpart}"
  create_supplement(manifestationid, type)
end

get '/iiif/:expressionpart/:manifestationpart/layer/transcription' do |expressionpart, manifestationpart|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  manifestationid = "#{expressionpart}/#{manifestationpart}"
  create_transcriptionlayer(manifestationid)
end

# hard coding these now for test
get '/iiif/:slug/list/translation/:folioid' do |slug, folioid|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  send_file "public/translation-#{slug}-#{folioid}.jsonld"
end
get '/iiif/:slug/list/comments/:folioid' do |slug, folioid|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  send_file "public/comments-#{slug}-#{folioid}.jsonld"
end
# end of hard coding for testing

get '/iiif/:expressionpart/:manifestationpart/list/transcription/:folioid' do |expressionpart, manifestationpart, folioid|
  headers( "Access-Control-Allow-Origin" => "*")
  content_type :json
  foliordfid = "<http://scta.info/resource/#{manifestationpart}/#{folioid}>"
  manifestationid = "#{expressionpart}/#{manifestationpart}"

#Surface was changed from hasFolioSide
  query = "SELECT ?x ?y ?w ?h ?position ?paragraph ?plaintext ?canvasid ?pnumber
          {
          ?zone <http://scta.info/property/hasSurface> #{foliordfid} .
          #{foliordfid} <http://scta.info/property/hasISurface> ?isurface .
          ?isurface <http://scta.info/property/hasCanvas> ?canvasid .
          ?zone <http://scta.info/property/ulx> ?x .
          ?zone <http://scta.info/property/uly> ?y .
          ?zone <http://scta.info/property/width> ?w .
          ?zone <http://scta.info/property/height> ?h .
          ?zone <http://scta.info/property/position> ?position .
          ?zone <http://scta.info/property/isZoneOf> ?paragraph .
          ?paragraph <http://scta.info/property/isTranscriptionOf> ?paragraphManifestation .
          ?paragraphManifestation <http://scta.info/property/isManifestationOf> ?paragraphExpression .
          ?paragraphExpression <http://scta.info/property/paragraphNumber> ?pnumber .
          ?paragraph <http://scta.info/property/plaintext> ?plaintext .
          }
          ORDER BY ?pnumber ?position
          "

        #@results = rdf_query(query)
        query_obj = Lbp::Query.new()
        @results = query_obj.query(query)


    annotationarray = []

      @results.each do |result|

        pid = result['paragraph'].to_s.split("/resource/").last
        position = result['position'].to_s
        paragraph = result['paragraph'].to_s
        paragraphtext = HTTParty.get(result['plaintext'].to_s)
        entryhash = {"@type" => "oa:Annotation",
        "@id" => "http://scta.info/iiif/#{manifestationid}/annotation/#{pid}/#{position}",
        "motivation" => "sc:painting",
        "resource" => {
            "@id" => "#{result[:plaintext]}",
            "@type" => "dctypes:Text",
            #"@type" => "cnt:ContentAsText",
            "chars" => "#{paragraphtext}</br> Metadata avaialble for this paragraph here: <a href='#{paragraph}'>#{paragraph}</a>.",
            "format" => "text/html"
        },
        "on" => "#{result[:canvasid]}#xywh=#{result[:x]},#{result[:y]},#{result[:w]},#{result[:h]}"
      }
        annotationarray << entryhash
       end

       annotationlistcontent = {"@context" => "http://iiif.io/api/presentation/2/context.jsonld",
        "@id" => "http://scta.info/iiif/#{manifestationid}/list/#{folioid}",
        "@type" => "sc:AnnotationList",
        "within" => {
          "@id" => "http://scta.info/iiif/#{manifestationid}/layer/transcription",
          "@type" => "sc:Layer",
          "label" => "Diplomatic Transcription"
        },
        "resources" => annotationarray
       }
    JSON.pretty_generate(annotationlistcontent)
end

get '/list/:type' do |type|

  @subjectid = "<http://scta.info/list/#{type}>"
  query = "#{prefixes}

          SELECT ?s ?o
          {
          ?s a <http://scta.info/resource/#{type}> .
          ?s <http://purl.org/dc/elements/1.1/title> ?o  .
          }
          ORDER BY ?s
          "

  @result = rdf_query(query)

  accept_type = request.env['HTTP_ACCEPT']

  if accept_type.include? "text/html"
    erb :subj_display

  else
    RDF::Graph.new do |graph|
      @result.each do |solution|
        s = RDF::URI(@subjectid)
        p = RDF::URI("http://scta.info/property/hasListMember")
        o = solution[:s]
        graph << [s, p, o]

      end
    end
  end
end

get '/?:p1?/?:p2?/?:p3?/?:p4?/?:p5?/?:p6?/?:p7?' do ||

  if params[:p7] != nil
    @subjectid = "<http://scta.info/#{params[:p1]}/#{params[:p2]}/#{params[:p3]}/#{params[:p4]}/#{params[:p5]}/#{params[:p6]}/#{params[:p7]}>"
  elsif params[:p6] != nil
    @subjectid = "<http://scta.info/#{params[:p1]}/#{params[:p2]}/#{params[:p3]}/#{params[:p4]}/#{params[:p5]}/#{params[:p6]}>"
  elsif params[:p5] != nil
    @subjectid = "<http://scta.info/#{params[:p1]}/#{params[:p2]}/#{params[:p3]}/#{params[:p4]}/#{params[:p5]}>"
  elsif params[:p4] != nil
    @subjectid = "<http://scta.info/#{params[:p1]}/#{params[:p2]}/#{params[:p3]}/#{params[:p4]}>"
  elsif params[:p3] != nil
    @subjectid = "<http://scta.info/#{params[:p1]}/#{params[:p2]}/#{params[:p3]}>"
  elsif params[:p2] != nil
    @subjectid = "<http://scta.info/#{params[:p1]}/#{params[:p2]}>"
  elsif params[:p1] != nil
    @subjectid = "<http://scta.info/#{params[:p1]}>"
  end

  query = "#{prefixes}

          SELECT ?p ?o ?ptype
          {
          #{@subjectid} ?p ?o .
          OPTIONAL {
              ?p rdfs:subPropertyOf ?ptype .
              }

          }
          ORDER BY ?p
          "

  #@result = rdf_query(query)
    #test using Lbp library
    query_obj = Lbp::Query.new()
    @result = query_obj.query(query)

  if params[:p1] == 'resource'
    @resourcetype = @result.dup.filter(:p => RDF::URI("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")).first[:o].to_s.split("/").last
  end

  accept_type = request.env['HTTP_ACCEPT']

  if accept_type.include? "text/html"

    @count = @result.count
    @title = @result.first[:o] # this works for now but doesn't seem like a great method since if the title ever ceased to the first triple in the query output this wouldn't work.



    @pubinfo = @result.dup.filter(:ptype => RDF::URI("http://scta.info/property/pubInfo"))
    @contentinfo = @result.dup.filter(:ptype => RDF::URI("http://scta.info/property/contentInfo"))
    @linkinginfo = @result.dup.filter(:ptype => RDF::URI("http://scta.info/property/linkingInfo"))
    @miscinfo = @result.dup.filter(:ptype => nil)


    @sameas = @result.dup.filter(:p => RDF::URI("http://www.w3.org/2002/07/owl#sameAs"))

    if @resourcetype == 'person' && @sameas.count > 0
      dbpediaAddress = @sameas[0][:o]
      dbpediaGraph = RDF::Graph.load(dbpediaAddress)
      query = RDF::Query.new({:person =>
                                  {
                                      RDF::URI("http://dbpedia.org/ontology/abstract") => :abstract
                                  #RDF::URI("http://dbpedia.org/ontology/birthDate") => :birthDate
                                  }
                             })

      result  = query.execute(dbpediaGraph)
      @english_result = result.find { |solution| solution.abstract.language == :en}
    end

  erb :obj_pred_display

  else
    RDF::Graph.new do |graph|
      @result.each do |solution|
        s = RDF::URI(@subjectid)
        p = solution[:p]
        o = solution[:o]
        graph << [s, p, o]

      end
    end
  end
end
