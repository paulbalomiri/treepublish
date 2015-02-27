
G= share.G
collection_name_appendix= new Meteor.EnvironmentVariable()


for func, idx in TP._collection_getters
  TP._collection_getters[idx]= do(func=func)-> (name)->
    appendix= collection_name_appendix.get() or ""
    return func(name+appendix)

base_collections_sub= Meteor.subscribe 'base-collections'
# create client-side result collections
_.extend TP.collections, _.object share.col_names.map (name)->
  res= "#{name}#{G.result_appendix}"
  [res, new Meteor.Collection(res)]   

in_result= (f)->
  return collection_name_appendix.withValue G.result_appendix, f
G= share.G

###
TestFunction that provides callbacks for befor/after subscription.
 @param `name` [String] the same as the first in Tinytest.add 
 @param `before_subscribe` [function] function to be called before subscription
 @param `after_subscribe` [function] function called after the publish subscription has been called 
 
 To test subscriptions:
 1. Call from before_subscribe any setup code, and call @subscribe at least once from within the function
 2. Analyze that the subscribe yields the expected results eithin `after_subscribe`

 If @subscribed is not called from `before_subscribe` a subscription 'result-collections' is called without any arguments.

 The subscription is automatically stopped after `before_subscribe`. 

###
Tinytest.publishTest= (name, before_subscribe, after_subscribe)->
  args=
    before_subscribe: before_subscribe or ->
    after_subscribe: after_subscribe
  Tinytest.addAsync name, (test, on_complete)->
    subscribe_args= null
    _.extend(test, share.test_case_result_mixin)
    this_arg=
      subscribe: (args...)->
        subscribe_args?=[]
        subscribe_args.push args
    if args.before_subscribe?
      ret= args.before_subscribe.call this_arg, test
      if ret? and (_.isString(ret) or _.isArray(ret) and ret.length and _.isString(ret[0]))
        subscribe_args?=[]
        subscribe_args.push ret
    subscribe_args?=['result-collections']
    ready= subscribe_args.map -> false
    ready_all= ->
      for x in ready
        unless x
          return false
      return true
    subscription_handlers=[]
    finisher= ->
      try
        args.after_subscribe?(test)
      finally
        for subscription_handler in subscription_handlers
          subscription_handler.stop()
        on_complete()
    for sub_args, idx in subscribe_args
      if _.isString sub_args
        sub_args= [sub_args]

      do(idx=idx)->
        subscription_handlers.push Meteor.subscribe sub_args... ,
          onReady: ()->
            try
              ready[idx]=true
            finally
              if ready_all()
                Meteor.setTimeout finisher, 100
          onError:(msg) ->
            try
              test.isFalse "Subscription failed for args, #{sub_args.join(",")}", msg.toString()
            finally
              ready[idx]=true
              if ready_all()
                finisher()

#allow access to all collections
for name, collection of TP.collections
  collection.allow
    insert:->true
    update:->true
    remove:->true


Tinytest.publishTest "test that a graph appears in the result set",
  (test)->
    G.set_graph
      A:'B0'
      B:""
    @subscribe "result-collections", 'A'
    #G.change_link "B1", "A0"
  ,
  (test)->
    g= G.get_graph()
    test.eqGraph  g,
        A:'B0'
        B:''
      ,
        "The published graph differs from the input graph"
    test.eqGraph  G.get_graph(true),
        A:'B0'
        B:''
      ,
        "The published result graph differs from the input graph"
oplog_cur=share.oplog.find()
Tinytest.publishTest "Test that a dependent component is added, and a not dependent is not added",
  (test)-> 
    G.set_graph
      A:"B0"
      B:';'
    @subscribe 'result-collections', 'A'
  ,
  (test)->
    g= G.get_graph true
    oplog= oplog_cur.fetch()
    test.eqGraph  g,
        A:'B0'
        B:''
      , 
        "B0 ought to be in the result set, B1 not."



Tinytest.publishTest "Test thant the coorect link dependency is added",
  (test)-> 
    G.set_graph
      A:"B1;"
      B:';A1'
    @subscribe 'result-collections', 'A'
  ,
  (test)->
    debugger
    g= G.get_graph true
    #oplog= @oplog_cur.fetch()
    
    test.eqGraph g, 
        A:'B1;'
        B:'1:A1'
      , 
        "B0 ought to be in the result set, B1 not."
Tinytest.publishTest "Test 4 level dependency",
  (test)-> 
    G.set_graph
      A:"B1;"
      B:';C1;C2'
      C:';D0;;'
      D:'B0;;;'
    @subscribe 'result-collections', 'A'
  ,
  (test)->
    g= G.get_graph true
    #oplog= @oplog_cur.fetch()
    
    test.eqGraph g, 
        A: 'B1;' # A is published as root LEVEL0
        B:[
          ''    #from D0 LEVEL4
          'C1' # from A0 LEVEL1
        ]
        C:[
          '1:D0'#from B1 LEVEL2
        ]
        D:[
          'B0' #from C1 LEVEL3
        ]
      , 
        "B0 ought to be in the result set, B1 not."

Tinytest.addWithGraphAsync "Test that link change unsubscribes one dependent and subsribes the new pointed to dependent",
    A:"B0"
    B:';'
    C:""
  ,
    (test, on_complete)-> 
      
      subscription= Meteor.subscribe 'result-collections', 'A',
        onReady: ->
          g= G.get_graph true
          test.eqGraph g,
            A:"B0"
            B:"" 
          G.change_link('A0', 'B1' )
          Meteor.autorun (c)->
            #wait for the change to come back from the server
            g= G.get_graph true
            if c.firstRun
              #here nothing has changed yet(no roundtrip from the server)
              test.eqGraph g,
                A:"B0"
                B:""
            else
              #here the results collection has been updated
              test.eqGraph g,
                A:"B1"
                B:""
              g.B.idx==1
              subscription.stop()
              c.stop()
              on_complete()
          
        






