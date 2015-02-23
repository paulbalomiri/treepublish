
collection_name_appendix= new Meteor.EnvironmentVariable()


for func, idx in TP._collection_getters
  TP._collection_getters[idx]= do(func=func)-> (name)->
    appendix= collection_name_appendix.get() or ""
    return func(name+appendix)
in_result= (f)->
  return collection_name_appendix.withValue G.result_appendix, f
G= share.G
Tinytest.publishTest= (name, before_subscribe, after_subscribe)->
  args=
    before_subscribe: before_subscribe or ->
    after_subscribe: after_subscribe
  Tinytest.addAsync name, (test, on_complete)->
    subscribe_args= null
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
    finisher= (test)->
      try
        args.after_subscribe?(test)
      finally
        debugger
        on_complete()
    for args, idx in subscribe_args
      if _.isString args
        args= [args]

      do(idx=idx)->
        debugger
        Meteor.subscribe args... ,
          onReady: ()->
            debugger
            try
              ready[idx]=true
            finally
              if ready_all()
                finisher()
          onError:(msg) ->
            try
              
              test.isFalse "Subscription failed for args, #{args.join(",")}", msg.toString()
            finally
              ready[idx]=true
              if ready_all()
                finisher()





Tinytest.publishTest "test that a graph appears in the result set",
  (test)->
    debugger
    G.set_graph
      A:'B0'
      B:''
  ,
  (test)->
    debugger
    g= G.load_graph()
    test.eqGraph  g,
        A:'B0'
        B:''
      ,
        "The published result graph differs from the input graph"

