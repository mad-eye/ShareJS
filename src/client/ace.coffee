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
  
  clearSessions = =>
    return unless @sessions
    currentSessionIds = []
    for sessionId, session of @sessions
      #Remove old selection
      editor.session.removeMarker session.marker if session.marker
      currentSessionIds.push sessionId
      #TODO: Remove gutter decoration
    sharejs._setActiveSessions currentSessionIds

  #Sessions carry the data for a given session:
  #session:
  #  cursor (share cursor)
  #  range (ace selection range)
  #  position (share position, cursor[1])ls
  #  marker (for selection)
  #
  updateCursors = =>
    clearSessions()
    @sessions ?= {}
    ranges = []
    #Keep track of sesionId:index for cursor color
    sessionIds = []
    console.log "###: cursors:", @cursors
    for own sessionId, cursor of @cursors
      @sessions[sessionId] = session = {}
      session.cursor = cursor
      range = cursorToRange(editorDoc, cursor)
      session.index = sharejs.getIndexForSession sessionId
      session.marker = editor.session.addMarker range, "foreign_selection foreign_selection_#{session.index} ace_selection", "line"
      cursor = [cursor, cursor] unless cursor instanceof Array
      session.position = cursor[1]
      ranges.push range if range
      sessionIds.push sessionId
    ranges.push cursor: null #need this for the user's own cursor
    console.log "Found sessionIds", sessionIds

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
      color = sharejs.getColorForSession sessionIds[i]
      console.log "Got color #{color} for session #{sessionIds[i]}"
      cursorElement.style.borderColor = color

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
    clearSelections()
    clearSessions()
    @editorAttached = false
    doc.removeListener 'remoteop', docListener
    doc.removeListener 'cursors', updateCursors
    editorDoc.removeListener 'change', editorListener
    editor.removeListener 'changeSelection', cursorListener
    delete doc.detach_ace

  return

##
# Colors section

#index:color
_colors = [
  "Brown",
  "DarkCyan",
  "DarkGreen",
  "DarkRed",
  "DarkSeaGreen",
  "MediumSlateBlue",
]

#sessionId:color
_sessionColors = {}

sharejs._setActiveSessions = (currentSessionIds) ->
  console.log "Setting activeSessions to", currentSessionIds
  for sessionId, color of _sessionColors
    unless sessionId in currentSessionIds
      delete _sessionColors[sessionId]
  console.log "New sessionColors", _sessionColors

sharejs.getColorForSession = (sessionId) ->
  color = _sessionColors[sessionId]
  console.log "Found color #{color} for #{sessionId}" if color?
  return color if color?
  assignedColors = _.values _sessionColors
  for color in _colors
    continue if color in assignedColors
    _sessionColors[sessionId] = color
    console.log "Found color #{color} for #{sessionId}"
    return color

sharejs.getIndexForSession = (sessionId) ->
  color = sharejs.getColorForSession sessionId
  index = _colors.indexOf color
  console.log "Found index #{index} for color #{color} for session #{sessionId}"
  return index

sharejs.getSessionColors = ->
  return _sessionColors

sharejs.getColors = ->
  return _colors

