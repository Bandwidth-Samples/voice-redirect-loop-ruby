require 'sinatra'
require 'bandwidth'

include Bandwidth
include Bandwidth::Voice

begin
    BANDWIDTH_USERNAME = ENV.fetch('BANDWIDTH_USERNAME')
    BANDWIDTH_PASSWORD = ENV.fetch('BANDWIDTH_PASSWORD')
    BANDWIDTH_ACCOUNT_ID = ENV.fetch('BANDWIDTH_ACCOUNT_ID')
    BANDWIDTH_VOICE_APPLICATION_ID = ENV.fetch('BANDWIDTH_VOICE_APPLICATION_ID')
    PORT = ENV.fetch('PORT')
    BASE_URL = ENV.fetch('BASE_URL')
rescue
    puts "Please set the environmental variables defined in the README"
    exit(-1)
end

set :port, PORT

bandwidth_client = Bandwidth::Client.new(
    voice_basic_auth_user_name: BANDWIDTH_USERNAME,
    voice_basic_auth_password: BANDWIDTH_PASSWORD
)
voice_client = bandwidth_client.voice_client.client

ACTIVE_CALLS = []

post '/callbacks/inbound' do
    callback_data = JSON.parse(request.body.read)

    if callback_data['eventType'] == 'initiate'
        ACTIVE_CALLS.append(callback_data['callId'])
    end

    response = Bandwidth::Voice::Response.new()
    if callback_data['eventType'] == 'initiate' or callback_data['eventType'] == 'redirect'
        ring = Bandwidth::Voice::Ring.new({
            :duration => 30
        })
        redirect = Bandwidth::Voice::Redirect.new({
            :redirect_url => '/callbacks/inbound'
        })

        response.push(ring)
        response.push(redirect)
    end

    return response.to_bxml()
end

post '/callbacks/goodbye' do
    callback_data = JSON.parse(request.body.read)
    
    response = Bandwidth::Voice::Response.new()
    if callback_data['eventType'] == 'redirect'
        speak_sentence = Bandwidth::Voice::SpeakSentence.new({
            :sentence => "The call has been updated. Goodbye"
        })
        response.push(speak_sentence)
    end

    return response.to_bxml()
end

delete '/calls/:call_id' do
    call_id = params[:call_id]

    if ACTIVE_CALLS.include?(call_id)
        body = ApiModifyCallRequest.new
        body.redirect_url = BASE_URL + "/callbacks/goodbye"
        voice_client.modify_call(BANDWIDTH_ACCOUNT_ID, call_id, :body => body)

        ACTIVE_CALLS.delete(call_id)
        return 'deleted %s' % [call_id]
    else
        status 404
        return 'call not found'
    end
end

get '/activeCalls' do
    return ACTIVE_CALLS.to_json()
end
