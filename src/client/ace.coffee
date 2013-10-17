# This is some utility code to connect an ace editor to a sharejs document.

requireImpl = if ace.require? then ace.require else require
Range = requireImpl("ace/range").Range

rangeToCursor = (editorDoc, range) ->
  return [editorDoc.positionToIndex(range.start), editorDoc.positionToIndex(range.end)]

cursorToRange = (editorDoc, cursor) ->
  cursor = [cursor, cursor] unless cursor instanceof Array
  start = editorDoc.indexToPosition cursor[0]
  end = editorDoc.indexToPosition cursor[1]
  range = Range.fromPoints start, end
  range.cursor = end
  return range

# Convert an ace delta into an op understood by share.js
applyToShareJS = (editorDoc, delta, doc) ->
  # Get the start position of the range, in no. of characters

  pos = rangeToCursor(editorDoc, delta.range)[0]
  pos = getStartOffsetPosition(delta.range)
  switch delta.action
    when 'insertText' then doc.insert pos, delta.text
    when 'removeText' then doc.del pos, delta.text.length
    
    when 'insertLines'
      text = delta.lines.join('\n') + '\n'
      doc.insert pos, text
      
    when 'removeLines'
      text = delta.lines.join('\n') + '\n'
      doc.del pos, text.length

    else throw new Error "unknown action: #{delta.action}"
  
  return

addCursorColorIndex = (cursorElement, index) ->
  classes = cursorElement.className.split " "
  newClasses = []
  for clazz in classes
    continue if clazz.indexOf('cursor_color_') == 0
    newClasses.push clazz
  newClasses.push "cursor_color_#{index}"
  cursorElement.className = newClasses.join " "

# Attach an ace editor to the document. The editor's contents are replaced
# with the document's contents unless keepEditorContents is true. (In which case the document's
# contents are nuked and replaced with the editor's).
window.sharejs.extendDoc 'attach_ace', (editor, keepEditorContents) ->
  @editorAttached = true
  throw new Error 'Only text documents can be attached to ace' unless @provides['text']

  doc = this
  editorDoc = editor.getSession().getDocument()
  editorDoc.setNewLineMode 'unix'

  check = ->
    window.setTimeout =>
      editorText = editorDoc.getValue()
      otText = doc.getText()

      if editorText != otText
        console.error "editor: #{editorText}"
        console.error "ot:     #{otText}"
        suppress = true
        editorDoc.setValue(otText)
        suppress = false
        doc.emit "warn", "OT/editor mismatch\nOT: #{otText}\neditor: #{editorText}"
    , 0


  if keepEditorContents
    doc.del 0, doc.getText().length
    doc.insert 0, editorDoc.getValue()
  else
    editorDoc.setValue doc.getText()

  check()

  # When we apply ops from sharejs, ace emits edit events. We need to ignore those
  # to prevent an infinite typing loop.
  suppress = false
  
  clearConnections = ->
    return unless doc.connections
    currentConnectionIds = []
    for connectionId, connection of doc.connections
      #Remove old selection
      editor.session.removeMarker connection.marker if connection.marker
      editor.session.removeGutterDecoration connection.position.row, "foreign_selection_#{connection.index}"
      currentConnectionIds.push connectionId
    sharejs._setActiveConnections currentConnectionIds

  #Connections carry the data for a given connection:
  #connection:
  #  cursor (share cursor)
  #  range (ace selection range)
  #  position (share position, cursor[1])ls
  #  marker (for selection)
  #
  updateCursors = ->
    clearConnections()
    doc.connections = {}
    ranges = []
    #Keep track of sesionId:index for cursor color
    connectionIds = []
    for own connectionId, cursor of doc.cursors
      doc.connections[connectionId] = connection = {}
      connection.cursor = cursor
      range = cursorToRange(editorDoc, cursor)
      #Selections
      connection.index = sharejs.getIndexForConnection connectionId
      connection.marker = editor.session.addMarker range, "foreign_selection foreign_selection_#{connection.index} ace_selection", "line"
      #Gutter decorations
      connection.position = range.end
      editor.session.addGutterDecoration connection.position.row, "foreign_selection_#{connection.index}"
      ranges.push range if range
      connectionIds.push connectionId
    ranges.push cursor: null #need this for the user's own cursor

    #Set cursors, which seems to have to be done in an arcane way
    #When the cursorLayer updates, it uses $selectionMarkers
    #We actually just use the `cursor` property of the elts of the
    #passed array.
    editor.session.$selectionMarkers = ranges
    cursorLayer = editor.renderer.$cursorLayer
    #rerender
    cursorLayer.update(editor.renderer.layerConfig)
    #color all the other users' cursors
    #the last cursor is the users, don't mess with it
    for cursorElement, i in cursorLayer.cursors[...-1]
      index = sharejs.getIndexForConnection connectionIds[i]
      addCursorColorIndex cursorElement, index
    ownCursor = cursorLayer.cursors[cursorLayer.cursors.length-1]
    addCursorColorIndex ownCursor, "00"

  # Listen for edits in ace
  editorListener = (change) ->
    return if suppress
    applyToShareJS editorDoc, change.data, doc
    updateCursors.call(doc)
    check()

  cursorListener = (change) ->
    #TODO pass which direction the cursor is selected
    cursor = rangeToCursor editorDoc, editor.getSelectionRange()
    doc.setCursor cursor

  replaceTokenizer = () ->
    oldTokenizer = editor.getSession().getMode().getTokenizer()
    oldGetLineTokens = oldTokenizer.getLineTokens
    oldTokenizer.getLineTokens = (line, state) ->
      if not state? or typeof state == "string" # first line
        cIter = doc.createIterator(0)
        state =
          modeState : state
      else
        cIter = doc.cloneIterator(state.iter)
        doc.consumeIterator(cIter, 1) # consume the \n from previous line

      modeTokens = oldGetLineTokens.apply(oldTokenizer, [line, state.modeState])
      docTokens = doc.consumeIterator(cIter, line.length)
      if (docTokens.text != line)
        return modeTokens

      return {
        tokens : doc.mergeTokens(docTokens, modeTokens.tokens)
        state :
          modeState : modeTokens.state
          iter : doc.cloneIterator(cIter)
      }

  replaceTokenizer() if doc.getAttributes?

  # Listen for remote ops on the sharejs document
  docListener = (op) ->
    suppress = true
    applyToDoc editorDoc, op
    suppress = false
    check()

  offsetToPos = (offset) ->
    editorDoc.indexToPosition offset

  doc.on 'insert', insertListener = (pos, text) ->
    suppress = true
    editorDoc.insert offsetToPos(pos), text
    suppress = false
    check()

  doc.on 'delete', deleteListener = (pos, text) ->
    suppress = true
    range = Range.fromPoints offsetToPos(pos), offsetToPos(pos + text.length)
    editorDoc.remove range
    suppress = false
    check()

  doc.on "cursors", updateCursors
  editorDoc.on 'change', editorListener
  editor.on "changeSelection", cursorListener


  doc.on 'refresh', refreshListener = (startoffset, length) ->
    range = Range.fromPoints offsetToPos(startoffset), offsetToPos(startoffset + length)
    editor.getSession().bgTokenizer.start(range.start.row)

  doc.detach_ace = ->
    #TODO: Hide cursor from other viewers
    doc.removeListener 'cursors', updateCursors
    doc.removeListener 'insert', insertListener
    doc.removeListener 'delete', deleteListener
    doc.removeListener 'remoteop', docListener
    doc.removeListener 'refresh', refreshListener
    editorDoc.removeListener 'change', editorListener
    editor.removeListener 'changeSelection', cursorListener
    delete doc.detach_ace
    clearConnections()
    @editorAttached = false

  return

##
# Colors section

_connections = []

sharejs._setActiveConnections = (currentConnectionIds) ->
  for connectionId, i in _connections
    unless connectionId in currentConnectionIds
      _connections[i] = null

sharejs.getIndexForConnection = (connectionId) ->
  #Find existing index
  index = _connections.indexOf connectionId
  return index if index > -1
  #Find first null
  for cid, i in _connections
    if cid == null
      _connections[i] = connectionId
      return i
  #Found no nulls, append
  length = _connections.push connectionId
  return (length - 1)

sharejs.getConnections = ->
  return _connections

