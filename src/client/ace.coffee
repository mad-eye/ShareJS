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
  
  updateCursors = ->
    @markers ?= []
    for marker in @markers
      editor.session.removeMarker marker
    ranges = []
    for own sessionId, cursor of @cursors
      range = cursorToRange(editorDoc, cursor) 
      @markers.push(editor.session.addMarker range, "foreign_selection ace_selection", "line")
      ranges.push range if range
    ranges.push cursor: null #need this for the user's own cursor

    editor.session.$selectionMarkers = ranges
    cursorLayer = editor.renderer.$cursorLayer
    #rerender
    cursorLayer.update(editor.renderer.layerConfig)
    colors = ["Brown", "DarkCyan", "DarkGreen", "DarkRed", "DarkSeaGreen", "MediumSlateBlue"]
    #color all the other users' cursors
    for cursorElement,i  in cursorLayer.cursors[1..]
      cursorElement.style.borderColor = colors[i%6]

  @on "cursors", updateCursors

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
    @editorAttached = false
    doc.removeListener 'remoteop', docListener
    doc.removeListener 'cursors', updateCursors
    editorDoc.removeListener 'change', editorListener
    editor.removeListener 'changeSelection', cursorListener
    delete doc.detach_ace

  return

