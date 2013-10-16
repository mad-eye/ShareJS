# This is some utility code to connect an ace editor to a sharejs document.

Range = require("ace/range").Range

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
  
  clearConnections = =>
    return unless @connections
    currentConnectionIds = []
    for connectionId, connection of @connections
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
  updateCursors = =>
    clearConnections()
    @connections = {}
    ranges = []
    #Keep track of sesionId:index for cursor color
    connectionIds = []
    for own connectionId, cursor of @cursors
      @connections[connectionId] = connection = {}
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
      color = sharejs.getColorForConnection connectionIds[i]
      cursorElement.style.borderColor = color
    ownCursor = cursorLayer.cursors[cursorLayer.cursors.length-1]
    ownCursor.style.borderColor = "Black"

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

  @on "cursors", updateCursors
  editorDoc.on 'change', editorListener
  editor.on "changeSelection", cursorListener

  # Listen for remote ops on the sharejs document
  docListener = (op) ->
    suppress = true
    applyToDoc editorDoc, op
    suppress = false
    check()

  offsetToPos = (offset) ->
    editorDoc.indexToPosition offset

  doc.on 'insert', (pos, text) ->
    suppress = true
    editorDoc.insert offsetToPos(pos), text
    suppress = false
    check()

  doc.on 'delete', (pos, text) ->
    suppress = true
    range = Range.fromPoints offsetToPos(pos), offsetToPos(pos + text.length)
    editorDoc.remove range
    suppress = false
    check()

  doc.detach_ace = ->
    doc.removeListener 'remoteop', docListener
    doc.removeListener 'cursors', updateCursors
    editorDoc.removeListener 'change', editorListener
    editor.removeListener 'changeSelection', cursorListener
    delete doc.detach_ace
    clearConnections()
    @editorAttached = false

  return

##
# Colors section

#index:color
_colors = [
  "#63782F", #Dark Green
  "#A13CB4", #Dark Purple
  "#FF913D", #Dark Orange
  "#00A3BB",
  "#FF007A", #Dark Pink
  "#58B442",
  "#63782F"
]

#TODO: Randomly choose a color.
overflowColor = "#99cc99"

#connectionId:color
_connectionColors = {}

sharejs._setActiveConnections = (currentConnectionIds) ->
  for connectionId, color of _connectionColors
    unless connectionId in currentConnectionIds
      delete _connectionColors[connectionId]

sharejs.getColorForConnection = (connectionId) ->
  color = _connectionColors[connectionId]
  return color if color?
  assignedColors = _.values _connectionColors
  for color in _colors
    continue if color in assignedColors
    _connectionColors[connectionId] = color
    return color
  #Didn't find any color, return the overflowColor
  #TODO: Randomly choose a color.
  return overflowColor

sharejs.getIndexForConnection = (connectionId) ->
  color = sharejs.getColorForConnection connectionId
  index = _colors.indexOf color
  return index if index > -1
  return null

sharejs.getConnectionColors = ->
  return _connectionColors

sharejs.getColors = ->
  return _colors

