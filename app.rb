# Sinatra example
#
# Call as http://localhost:4567/sparql?query=uri,
# where `uri` is the URI of a SPARQL query, or
# a URI-escaped SPARQL query, for example:
#   http://localhost:4567/?query=SELECT%20?s%20?p%20?o%20WHERE%20%7B?s%20?p%20?o%7D
require 'sinatra'
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
#require 'sinatra/linkeddata' doesn't work but I need this for content negotiation

require_relative 'lib/metadata'

require 'pry'
#require 'ruby-debug-ide'
include RDF



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





def rdf_query(query)
  
  if ENV['RACK_ENV'] == "production"
    sparqlendpoint = "http://localhost:31867/ds/query"
  else
    sparqlendpoint = "http://localhost:3030/ds/query"
  end

  sparql = SPARQL::Client.new(sparqlendpoint)
  result = sparql.query(query)

  return result
end


def query_display_simple(query)
  result = rdf_query(query)
  result.each_solution do |solution|
  puts solution.inspect
  end
end

def URLConvert (url)
  url_hash = {}
  if url.to_str.include? 'http://scta.info'
    url_hash[:url_label] = url.parent.to_s
    url_hash[:url_base] = url.to_str.gsub(url.parent.to_s, '')
    url_hash[:url_link] = url.to_str.gsub('http://scta.info', '')

  elsif url.qname
    url_hash[:url_label] = url.qname[0].to_s + ":"
    url_hash[:url_base] = url.qname[1].to_s
    url_hash[:url_link] = url.to_str
  else
    url_hash[:url_label] = url.parent.to_s
    url_hash[:url_base] = url.to_str.gsub(url.parent.to_s, '')
    url_hash[:url_link] = url.to_str
  end
  return url_hash
end


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
            ?item a <http://scta.info/resource/item> .
          }
          "
  commentaryquery = "#{prefixes}

          SELECT count(distinct ?com) {
            ?com a <http://scta.info/resource/commentarius> .
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
  @quotationcount = rdf_query(quotationquery).first[:".1"]
  @quotescount = rdf_query(quotesquery).first[:".1"]
  @itemcount = rdf_query(itemquery).first[:".1"]
  @commentarycount = rdf_query(commentaryquery).first[:".1"]
  @namecount = rdf_query(namequery).first[:".1"]
  @workcount = rdf_query(workquery).first[:".1"]


  erb :index
end

get '/practice' do

  graph = RDF::Graph.load("public/pp-projectdata.rdf")
  query = RDF::Query.new({
                   :subject => {
                       RDF.type  => RDF::URI("http://scta.info/resource/item"),
                       DC11.title => :title,
                      }
                    })

  query.execute(graph).each do |solution|
    
    puts "title=#{solution.title}"
  end
  end

  get '/construct' do

    query = "#{prefixes}

    CONSTRUCT {
      <http://scta.info/text/plaoulcommentary/commentary> sctap:quotes ?quote .
      }

    WHERE  {
      <http://scta.info/text/plaoulcommentary/commentary> dcterms:hasPart ?p .
      ?p sctap:quotes ?quote .

      }"

    @result = rdf_query(query)
    @result_hash = []
    @predicate = "sctap:quotes"
    @result.each_statement do |statement|
        @result_hash << statement.object

    end
  erb :practice
  #binding.pry



end

get '/main' do
  puts "text"
  erb :main
end

get '/scta' do
  query = "#{prefixes}

          SELECT ?s ?o
          {
          ?s a <http://scta.info/resource/commentarius> .
          ?s <http://purl.org/dc/elements/1.1/title> ?o  .
          }
          ORDER BY ?s
          "
  @category = 'commentary'
  @result = rdf_query(query)


  erb :subj_display
end

get '/api' do 
  erb :api
end

get '/search' do
  erb :search
end

get '/searchresults' do


  @post = "#{params[:search]}"
  @category = "#{params[:category]}"
  
    if @category == "questionTitle"
      type = "item"
      predicate = "<http://scta.info/property/questionTitle>"
    else
      type = @category
      predicate = "<http://purl.org/dc/elements/1.1/title>"
    end
    
    query = "#{prefixes}

          SELECT ?s ?o
          {

          ?s a <http://scta.info/resource/#{type}> .
          ?s #{predicate} ?o  .
          FILTER (REGEX(STR(?o), '#{@post}', 'i')) .
          }
          ORDER BY ?s
          "
    
  #query_display_simple(query)
  @result = rdf_query(query)
  erb :searchresults
end

post '/sparqlquery' do

  query = "#{params[:query]}"
  query_display_simple(query)
end


get '/iiif/:msname/manifest' do |msname|
  headers( "Access-Control-Allow-Origin" => "*")
  send_file "public/#{msname}.json"
end

get '/iiif/pg-lon/list/L1r' do 
  headers( "Access-Control-Allow-Origin" => "*")
  send_file "public/pg-lon-list-l1r.json"
end
get '/iiif/pg-lon/text/test.txt' do 
  headers( "Access-Control-Allow-Origin" => "*")
  send_file "public/testtext.txt"
end

=begin
get '/property/:property' do |property|
  query = "#{prefixes}

          SELECT ?p ?o
          {
          <http://scta.info/property/#{relation}> ?p ?o  .
          
          }
          ORDER BY ?s
          "
          @result = rdf_query(query)
          erb :obj_pred_display

end
=end

=begin
get '/property/:property/:subprop' do |property, subprop|
  query = "#{prefixes}

          SELECT ?p ?o
          {
          <http://scta.info/property/#{relation}/#{subprop}> ?p ?o  .

          }
          ORDER BY ?s
          "
  @result = rdf_query(query)
  erb :obj_pred_display

end
=end


=begin
get '/text/:cid/:category' do |cid, category|
  #this isn't really going to work because grandhildren parts will not be identified.
  query = "#{prefixes}

          SELECT ?s ?o
          {
          ?s a <http://scta.info/resource/#{category}> .
          ?s dc:isPartOf <http://scta.info/#{cid}/commentary>  .
          ?s <http://purl.org/dc/elements/1.1/title> ?o  .
          }
          OR
          {
          ?s a <http://scta.info/resource/#{category}> .
          ?s dc:hasPart ?parent .
          ?parent dc:isPartOf <http://scta.info/#{cid}/commentary>  .
          }

          ?s <http://purl.org/dc/elements/1.1/title> ?o  .
          }
          ORDER BY ?s
          " 

        @category = category
        @result = rdf_query(query)
        accept_type = request.env['HTTP_ACCEPT']
        if accept_type.include? "text/html"
            erb :subj_display
        else
        RDF::Graph.new do |graph|
          @result.each do |solution|
            s = solution[:s]
            o = solution[:o]
            graph << [s, RDF::DC.title, o]
            end
        end
      end
end
=end

=begin
get '/resource/:category/:id' do |category, id|


@category = category
@id = id                
@subjectid = "<http://scta.info/resource/#{@category}/#{@id}>"

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
          @result = rdf_query(query)
          accept_type = request.env['HTTP_ACCEPT']

      if accept_type.include? "text/html"

          @count = @result.count
          @title = @result.first[:o] # this works for now but doesn't seem like a great method since if the title ever ceased to the first triple in the query output this wouldn't work.

          @pubinfo = @result.dup.filter(:ptype => RDF::URI("http://scta.info/property/pubInfo"))
          @contentinfo = @result.dup.filter(:ptype => RDF::URI("http://scta.info/property/contentInfo"))
          @linkinginfo = @result.dup.filter(:ptype => RDF::URI("http://scta.info/property/linkingInfo"))
          #@referenceinfo = @resutl.dup.filter(:ptype => RDF::URI("http://scta.info/property/referenceInfo"))
          @miscinfo = @result.dup.filter(:ptype => nil)

          erb :obj_pred_display
          else
          RDF::Graph.new do |graph|
            @result.each do |solution|
              s = RDF::URI("http://scta.info/#{@category}/#{@id}")
              p = solution[:p]
              o = solution[:o]
              graph << [s, p, o]

            end
  end
end
  
end
=end
=begin
get '/text/:cid/commentary' do |cid, commentary|


  @commentary = commentary
  @cid = cid
  @subjectid = "<http://scta.info/#{prefix}/#{@cid}/commentary>"

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

  @result = rdf_query(query)
  accept_type = request.env['HTTP_ACCEPT']

  if accept_type.include? "text/html"

    @count = @result.count
    @title = @result.first[:o] # this works for now but doesn't seem like a great method since if the title ever ceased to the first triple in the query output this wouldn't work.

    @pubinfo = @result.dup.filter(:ptype => RDF::URI("http://scta.info/property/pubInfo"))
    @contentinfo = @result.dup.filter(:ptype => RDF::URI("http://scta.info/property/contentInfo"))
    @linkinginfo = @result.dup.filter(:ptype => RDF::URI("http://scta.info/property/linkingInfo"))
    @miscinfo = @result.dup.filter(:ptype => nil)

    erb :obj_pred_display
  else
    RDF::Graph.new do |graph|
      @result.each do |solution|
        s = RDF::URI("http://scta.info/text/#{@cid}/#{@category}/#{@id}")
        p = solution[:p]
        o = solution[:o]
        graph << [s, p, o]

      end
    end
  end


end
=end



=begin

get '/text/:cid/:category/:id' do |cid, category, id|


  @category = category
  @id = id
  @cid = cid
  @subjectid = "<http://scta.info/text/#{@cid}/#{@category}/#{@id}>"

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

  @result = rdf_query(query)
  
  accept_type = request.env['HTTP_ACCEPT']

  if accept_type.include? "text/html"

    @count = @result.count
    @title = @result.first[:o] # this works for now but doesn't seem like a great method since if the title ever ceased to the first triple in the query output this wouldn't work.

    @pubinfo = @result.dup.filter(:ptype => RDF::URI("http://scta.info/property/pubInfo"))
    @contentinfo = @result.dup.filter(:ptype => RDF::URI("http://scta.info/property/contentInfo"))
    #@referenceinfo = @resutl.dup.filter(:ptype => RDF::URI("http://scta.info/property/referenceInfo"))
    @linkinginfo = @result.dup.filter(:ptype => RDF::URI("http://scta.info/property/linkingInfo"))
    @miscinfo = @result.dup.filter(:ptype => nil)

    erb :obj_pred_display
  else
    RDF::Graph.new do |graph|
      @result.each do |solution|
        s = RDF::URI("http://scta.info/text/#{@cid}/#{@category}/#{@id}")
        p = solution[:p]
        o = solution[:o]
        graph << [s, p, o]

      end
    end
  end

end
=end
get '/textsearch/:string' do |string| 

@searchstring = string
response = HTTParty.get("http://localhost:8983/solr/collection1/select?q=#{string}&rows=100&wt=json&indent=true") 
json = JSON.parse(response.body)
response_hash = json.to_hash
@docs_array = response_hash["response"]["docs"]

erb :textsearch
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

get '/?:p1?/?:p2?/?:p3?/?:p4?' do ||

  if params[:p4] != nil
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

  @result = rdf_query(query)

  if params[:p1] == 'resource'
    @resourcetype = params[:p2]
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
      #binding.pry
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
















