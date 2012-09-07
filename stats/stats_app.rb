require 'sinatra'
require 'json'


class StatsApp < Sinatra::Base
  configure :production, :development do
    set :stats, {}
    puts "configured app"
  end

  post '/stats/:product/:metric' do
    settings.stats[params[:product]] ||= {}
    settings.stats[params[:product]][params[:metric]] ||= 0
    settings.stats[params[:product]][params[:metric]] += 1
    "ok"
  end

  get '/stats/:product' do
    settings.stats[params[:product]].to_json
  end
end
