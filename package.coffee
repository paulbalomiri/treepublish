 Package.describe
    name: 'pba:treepublish'
    description: 'publishing gor linked collections'
  Package.on_use (api) ->
    client = 'client'
    server = 'server'
    both = [
      client
      server
    ]
    both_f = [ 'init.coffee' ]
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
  return