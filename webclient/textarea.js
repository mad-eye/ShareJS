// Generated by CoffeeScript 1.6.3
(function() {
  var applyChange, hueForId;

  applyChange = function(doc, oldval, newval, cursor) {
    var commonEnd, commonStart;
    if (oldval === newval) {
      return;
    }
    commonEnd = 0;
    while (oldval.charAt(oldval.length - 1 - commonEnd) === newval.charAt(newval.length - 1 - commonEnd) && commonEnd < oldval.length && commonEnd < newval.length && cursor + commonEnd < newval.length) {
      commonEnd++;
    }
    commonStart = 0;
    while (oldval.charAt(commonStart) === newval.charAt(commonStart) && commonEnd + commonStart < oldval.length && commonEnd + commonStart < newval.length) {
      commonStart++;
    }
    if (oldval.length !== commonStart + commonEnd) {
      doc.del(commonStart, oldval.length - commonStart - commonEnd);
    }
    if (newval.length !== commonStart + commonEnd) {
      return doc.insert(commonStart, newval.slice(commonStart, newval.length - commonEnd));
    }
  };

  hueForId = function(id) {
    return id * 133 % 360;
  };

  window.sharejs.extendDoc('attach_textarea', function(elem) {
    var checkForChanges, ctx, deleteListener, doc, drawCursors, event, events, insertListener, prevvalue, replaceText, _i, _len,
      _this = this;
    window.e = elem;
    doc = this;
    elem.value = this.getText();
    prevvalue = elem.value;
    this.setCursor(elem.selectionStart);
    ctx = typeof document.getCSSCanvasContext === "function" ? document.getCSSCanvasContext('2d', 'cursors', elem.offsetWidth, elem.offsetHeight) : void 0;
    drawCursors = function() {
      var c, cs, div, e, getPos, id, k, metrics, p1, p2, pos, text, v, y, _ref;
      if (!ctx) {
        return;
      }
      div = document.createElement('div');
      text = div.appendChild(document.createTextNode(elem.value));
      div.style.width = "" + elem.offsetWidth + "px";
      div.style.height = "" + elem.offsetHeight + "px";
      cs = getComputedStyle(elem);
      for (k in cs) {
        v = cs[k];
        div.style[k] = v;
      }
      document.body.appendChild(div);
      getPos = function(pos) {
        var divrect, h, remainder, span, spanrect, x, y;
        span = document.createElement('span');
        if (pos === 0) {
          if (elem.value.length) {
            div.insertBefore(span, text);
          } else {
            div.appendChild(span);
          }
        } else if (pos < elem.value.length) {
          remainder = text.splitText(pos);
          div.insertBefore(span, remainder);
        } else {
          div.appendChild(span);
        }
        span.innerText = ' ';
        divrect = div.getBoundingClientRect();
        spanrect = span.getBoundingClientRect();
        x = spanrect.left - divrect.left;
        y = spanrect.top - divrect.top;
        h = spanrect.height;
        div.removeChild(span);
        div.normalize();
        return {
          x: Math.round(x),
          y: Math.round(y) - elem.scrollTop - 1,
          h: h
        };
      };
      ctx.clearRect(0, 0, elem.offsetWidth, elem.offsetHeight);
      ctx.font = '14px monaco';
      ctx.textBaseline = 'top';
      ctx.textAlign = 'right';
      ctx.lineWidth = 3;
      _ref = doc.cursors;
      for (id in _ref) {
        c = _ref[id];
        metrics = ctx.measureText(id);
        try {
          if (typeof c === 'number') {
            pos = getPos(c);
            ctx.fillStyle = "hsl(" + (hueForId(id)) + ", 90%, 34%)";
            ctx.fillRect(pos.x - 1, pos.y, 2, pos.h);
            y = pos.y + 2;
            ctx.beginPath();
            ctx.moveTo(pos.x, y);
            ctx.lineTo(elem.scrollWidth, y);
            ctx.strokeStyle = "hsla(" + (hueForId(id)) + ", 90%, 34%, 0.3)";
            ctx.stroke();
            ctx.fillStyle = "hsla(" + (hueForId(id)) + ", 90%, 34%, 0.6)";
            ctx.fillRect(elem.scrollWidth - metrics.width - 5, y - 2, metrics.width + 5, 21);
          } else {
            p1 = getPos(Math.min(c[0], c[1]));
            p2 = getPos(Math.max(c[0], c[1]));
            y = p1.y + 2;
            if (!(p1.h && p2.h)) {
              continue;
            }
            ctx.fillStyle = "hsla(" + (hueForId(id)) + ", 90%, 34%, 0.5)";
            if (p1.y === p2.y) {
              ctx.fillRect(p1.x, p1.y, p2.x - p1.x, p1.h);
              ctx.beginPath();
              ctx.moveTo(p1.x, y);
              ctx.lineTo(elem.scrollWidth, y);
              ctx.strokeStyle = "hsla(" + (hueForId(id)) + ", 90%, 34%, 0.3)";
              ctx.stroke();
              ctx.fillStyle = "hsla(" + (hueForId(id)) + ", 90%, 34%, 0.6)";
              ctx.fillRect(elem.scrollWidth - metrics.width - 5, y - 2, metrics.width + 5, 21);
            } else {
              ctx.fillRect(p1.x, p1.y, elem.scrollWidth - p1.x, p1.h);
              ctx.fillRect(0, p1.y + p1.h, elem.scrollWidth, p2.y - p1.y - p1.h);
              ctx.fillRect(0, p2.y, p2.x, p2.h);
            }
          }
          ctx.fillStyle = 'white';
          ctx.fillText(id, elem.scrollWidth - 3, y);
        } catch (_error) {
          e = _error;
          console.error(e.stack);
        }
      }
      return document.body.removeChild(div);
    };
    drawCursors();
    replaceText = function(newText) {
      var anchor, focus, scrollTop, _ref, _ref1, _ref2;
      scrollTop = elem.scrollTop;
      elem.value = newText;
      if (elem.scrollTop !== scrollTop) {
        elem.scrollTop = scrollTop;
      }
      if (window.document.activeElement === elem) {
        elem.selectionStart = newSelection[0], elem.selectionEnd = newSelection[1];
      }
      if (typeof doc.cursor === 'number') {
        return elem.selectionStart = elem.selectionEnd = doc.cursor;
      } else {
        _ref = doc.cursor, anchor = _ref[0], focus = _ref[1];
        if (anchor < focus) {
          return _ref1 = [anchor, focus], elem.selectionStart = _ref1[0], elem.selectionEnd = _ref1[1], _ref1;
        } else {
          _ref2 = [focus, anchor], elem.selectionStart = _ref2[0], elem.selectionEnd = _ref2[1];
          return elem.selectionDirection = 'backward';
        }
      }
    };
    this.on('insert', insertListener = function(pos, text) {
      prevvalue = elem.value.replace(/\r\n/g, '\n');
      return replaceText(prevvalue.slice(0, pos) + text + prevvalue.slice(pos));
    });
    this.on('delete', deleteListener = function(pos, text) {
      prevvalue = elem.value.replace(/\r\n/g, '\n');
      return replaceText(prevvalue.slice(0, pos) + prevvalue.slice(pos + text.length));
    });
    this.on('cursors', drawCursors);
    checkForChanges = function(event) {
      return setTimeout(function() {
        if (elem.selectionStart === elem.selectionEnd) {
          doc.setCursor(elem.selectionStart);
        } else {
          if (elem.selectionDirection === 'backward') {
            doc.setCursor([elem.selectionEnd, elem.selectionStart]);
          } else {
            doc.setCursor([elem.selectionStart, elem.selectionEnd]);
          }
        }
        if (elem.value !== prevvalue) {
          prevvalue = elem.value;
          applyChange(doc, doc.getText(), elem.value.replace(/\r\n/g, '\n'), elem.selectionEnd);
          return drawCursors();
        }
      }, 0);
    };
    events = ['textInput', 'keydown', 'keyup', 'select', 'cut', 'paste', 'click', 'mousemove', 'focus'];
    for (_i = 0, _len = events.length; _i < _len; _i++) {
      event = events[_i];
      if (elem.addEventListener) {
        elem.addEventListener(event, checkForChanges, false);
      } else {
        elem.attachEvent('on' + event, checkForChanges);
      }
    }
    elem.addEventListener('scroll', drawCursors, false);
    window.addEventListener('resize', drawCursors, false);
    return elem.detach_share = function() {
      var _j, _len1, _results;
      _this.removeListener('insert', insertListener);
      _this.removeListener('delete', deleteListener);
      _this.removeListener('cursors', drawCursors);
      _results = [];
      for (_j = 0, _len1 = events.length; _j < _len1; _j++) {
        event = events[_j];
        if (elem.removeEventListener) {
          _results.push(elem.removeEventListener(event, checkForChanges, false));
        } else {
          _results.push(elem.detachEvent('on' + event, checkForChanges));
        }
      }
      return _results;
    };
  });

}).call(this);
