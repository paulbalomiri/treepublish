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
  
  #stage 1 (declarations needed for testing) (cntains init code for client and server)
  api.add_files  ['meteor-unofficial' ,'live-links-init'].map (f)->"tests/#{f}.coffee"
  
  #stage 2 client/server tests (also contain client/server specific init)
  api.add_files ['tests/live-links-client.coffee'], ['client']
  api.add_files ['tests/live-links-server.coffee'], ['server']
  #stage 3 common tests
  api.add_files ['tests/live-links-common.coffee'] 