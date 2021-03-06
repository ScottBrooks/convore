require 'yaml'
module Convore
	class Client
		attr_accessor :thread, :stream, :cursor, :username, :password

		def initialize
			@stream ||= []
			@ts ||= Time.now.to_f
		end
		
		def listen
			raise Exception.new("username and password need to be set to listen to /live") if !username || !password

			@thread = Thread.fork {
				Net::HTTP.start('convore.com', 443, nil, nil, nil, nil, {:use_ssl => true}) {|http|
					req = Net::HTTP::Get.new("/api/live.json?cursor=#{@cursor if @cursor}")
					req.basic_auth(username, password)
					req.set_content_type('application/json')
					response = http.request(req)
					
					Thread.current[:response] = response.body
				}
			}
		end

		def process_response(response)
			json = JSON.parse(response)

			if json['messages']
				json['messages'].each {|msg|
					if msg['_ts'] && @ts < msg['_ts']
						case msg['kind']
						when 'message' then
							stream.unshift(Message.from_json(msg))
						when 'topic' then
							stream.unshift(Topic.from_json(msg))
						when 'star', 'unstar' then
							stream.unshift(Star.from_json(msg))
						end
						@ts = msg['_ts'] if msg['_ts']
						@cursor = msg['_id'] if msg['_id']
					end
				}
			end
		end
		
		def poll(wait = 0.05)
			if t = @thread.join(wait)
				listen unless @thread.alive?
				process_response(t[:response])
			end				
		end

		def groups
			response = Convore::API.get("/api/groups.json", @username, @password)

			json = JSON.parse(response.body)
			json["groups"].map do |group|
				Group.from_json(group)
			end
		end

		def topics(group)
			response = Convore::API.get("/api/groups/#{group}/topics.json", @username, @password)

			json = JSON.parse(response.body)
			json["topics"].map do |topic|
				Topic.from_json(topic)
			end
		end

		def create_message(topic_id, message)
			body = "message=#{message}"
			response = Convore::API.post("/api/topics/#{topic_id}/messages/create.json", {"message"=>message}, @username, @password)
		end
	end
end
