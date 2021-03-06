#  Useful utility functions.
Annotator.Readmill.utils = do ->
  # Create private jQuery variable for this object.
  jQuery = Annotator.$

  # Public: Binds context of handler methods (beginning with "_on") on the
  # provided object to the provided object. This is useful for binding scope
  # on multiple methods without having to use CoffeeScripts => syntax which
  # will add a new __bind() call for every method.
  #
  # obj    - Object to bind methods.
  # prefix - An alternative prefix string (default: "_on").
  #
  # Examples
  #
  #   class Handler
  #     constructor: ->
  #       utils.proxyHandlers this
  #       jQuery("body").bind
  #         click: _onClick, submit: _onSubmit, change: _onChange
  #     log: (msg) -> console.log msg
  #     _onClick:  -> @log "clicked"
  #     _onSubmit: -> @log "submitted"
  #     _onChange: -> @log "changed"
  #
  # Returns
  proxyHandlers: (obj, prefix="_on") ->
    for key, value of obj
      if key.indexOf(prefix) is 0 and typeof value is "function"
        obj[key] = jQuery.proxy obj, key
    obj

  # Public: Serializes an object literal into a query string suitable
  # for use in a url. Escapes key and value parameters into url safe
  # entities.
  #
  # obj - An object to serailize.
  # sep - The seperator to join parameters (default: "&")
  # eq  - The seperator between key and value (default: "=")
  #
  # Examples
  #
  #   utils.serializeQueryString(dog: "woof", cat: "meow")
  #   #=> "dog=woof&cat=meow"
  #
  #   utils.serializeQueryString(dog: "woof", cat: "meow", "\n", ": ")
  #   #=> "dog: woof\ncat: meow"
  #
  # Returns newly created string.
  serializeQueryString: (obj, sep="&", eq="=") ->
    esc = window.encodeURIComponent
    ("#{esc(key)}#{eq}#{esc(value)}" for own key, value of obj).join(sep)

  # Public: parses a query string extracted from a url. Also decodes
  # any escaped key/values.
  #
  # obj - An string to parse.
  # sep - The seperator to join parameters (default: "&")
  # eq  - The seperator between key and value (default: "=")
  #
  # Examples
  #
  #   utils.parseQueryString("dog=woof&cat=meow")
  #   #=> {dog: "woof", cat: "meow"}
  #
  # Returns an object of key value pairs.
  parseQueryString: (str, sep="&", eq="=") ->
    obj = {}
    decode = window.decodeURIComponent
    for param in str.split(sep)
      [key, value] = param.split(eq)
      obj[decode(key)] = decode value
    obj

  # Takes a dom node and returns the text content of all previous nodes.
  #
  # highlight - A DOM node.
  #
  # Returns a string fo extracted text.
  preText: (highlight) ->
    collected = while highlight = highlight.previousSibling then highlight
    jQuery(collected.reverse()).text()

  # Takes a dom node and extracts the text from all successive siblings.
  #
  # Highlight - A DOM node.
  #
  # Returns a string.
  postText: (highlight) ->
    collected = while highlight = highlight.nextSibling then highlight
    jQuery(collected).text()

  # Public: Extract the locators object from an annotation.
  #
  # annotation - An annotation object to extract the locator from.
  #
  # Returns a object to be used in the locators key.
  locatorsFromAnnotation: (annotation) ->
    highlights = annotation.highlights

    pre   = @preText(highlights[0])
    post  = @postText(highlights[highlights.length - 1])

    pre: pre
    mid: annotation.quote
    post: post
    xpath: annotation.ranges[0]
    file_id: annotation.page

  # Public: Takes an annotation object and returns a highlight object
  # suitable for submission to the Readmill server.
  #
  # annotation - An annotation object.
  #
  # Examples
  #
  #   _onAnnotationCreated: (ann) ->
  #     highlight = utils.highlightFromAnnotation(ann)
  #
  # Returns a highlight object.
  highlightFromAnnotation: (annotation) ->
    locator = @locatorsFromAnnotation(annotation)
    # See: https://github.com/Readmill/API/wiki/Readings
    {
      id: annotation.id
      content: annotation.quote
      highlighted_at: undefined
      locators: locator
    }

  # Public: Takes an annotation object and returns an object suitable for
  # submission to the Readmill server.
  #
  # annotation - An annotation object.
  #
  # Examples
  #
  #   _onAnnotationCreated: (ann) ->
  #     comment = utils.commentFromAnnotation(ann)
  #
  # Returns a comment object.
  commentFromAnnotation: (annotation) ->
    # Documentation seems to indicate this should be wrapped in an object
    # with a "content" property but that does not seem to work with the
    # POST /highlights API.
    # See: https://github.com/Readmill/API/wiki/Readings
    {content: annotation.text}

  # Public: Transform utility to get an annotation object from a provided
  # highlight. This method also needs to fetch the comment from a
  # seperate endpoint so returns a jQuery.Deferred() promise that will
  # call all "done" callbacks when completed.
  #
  # If the highlight fails to parse then deferred.reject() will be called
  # with no arguments.
  #
  # highlight - The highlight object returned from the Readmill API.
  # client    - An instance of Readmill.Client.
  #
  # Examples
  #
  #   def = utils.annotationFromHighlight(highlight, client)
  #   def.done (annotation) -> console.log annotation
  #   def.fail -> console.log "Couldn't retrieve annotation"
  #
  # Returns a jQuery.Deferred() promise.
  annotationFromHighlight: (highlight, client) ->
    # Try and extract annotation metadata from the locators object.
    meta = (try ranges: [highlight.locators.xpath] catch e then null) if highlight.locators.xpath
    meta = (try ranges: JSON.parse(highlight.pre) catch e then null)  unless meta
    deferred = new jQuery.Deferred()

    if meta
      annotation =
        id: highlight.id
        page: highlight.locators.file_id or meta.page
        quote: highlight.content
        text: ""
        ranges: meta.ranges
        highlightUrl: highlight.uri
        commentUrl: ""
        commentsUrl: highlight.comments

      client.request(url: highlight.comments).fail(deferred.reject).done (comments) ->
        if comments.length
          annotation.text = comments[0].content
          annotation.commentUrl = comments[0].uri
        deferred.resolve annotation
    else
      deferred.reject()
    deferred.promise()
