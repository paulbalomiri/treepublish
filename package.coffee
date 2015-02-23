Package.describe
  name: 'pba:treepublish'
  description: 'publishing gor linked collections'
Npm.depends
  'strongly-connected-components':'1.0.1'
Package.on_use (api) ->
  client = 'client'
  server = 'server'
  both = [
    client
    server
  ]
  both_f = [ 
    'init.coffee' 
    ##'reachability.coffee' 
  ]
  client_f = []
  server_f = [ 'treepublish.coffee' ]
  api.use [
    'coffeescript'
    'check'
    'alethes:lodash@0.7.1'
    'pba:lodash-deep'
  ], both
  api.use [
    'entity-base'
    'entity-links'

  ], both, weak: true
  api['export'] 'TP'
  api.add_files both_f, both
  api.add_files server_f, server
  api.add_files client_f, client

Package.on_test (api)->

  api.use [ 'coffeescript' ,'alethes:lodash@0.7.1' ,'mongo', 'tinytest', 'pba:treepublish', 'pba:lodash-deep'] 
  api.add_files  ['meteor-unofficial' ,'live-links'].map (f)->"tests/#{f}.coffee"
  api.add_files ['tests/live-links-client.coffee'], ['client']
  api.add_files ['tests/live-links-server.coffee'], ['server']