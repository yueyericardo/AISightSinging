import MuseScore 3.0
import QtQuick 2.9
MuseScore {
  property string pname: "Add fixed Do solfa names as lyrics"
  menuPath: "Plugins." + pname
  version: "20230223B";
  id: pluginscope
  Component.onCompleted: {
    if (mscoreMajorVersion >= 4) {
      pluginscope.title = pluginscope.pname
      // some_id.thumbnailName = "thumbnail.png";
      // some_id.categoryCode = "some_caregory";
    }
  }

  // Function to determine if the key signature is sharp, flat, or natural
  function getKeySignature(cursor) {
    var ks = cursor.keySignature;
    if (ks > 0)
      return "sharp";
    else if (ks < 0)
      return "flat";
    else
      return "natural";
  }

  function nameNote(note, keySig) {
    // Adjust solfa names based on key signature
    var solfaNamesSharp = [
      "Do", "Di", "Re", "Ri", "Mi", "Fa", "Fii", "Sol", "Si", "La", "Li", "Ti"
    ];
    var solfaNamesFlat = [
      "Do", "Ra", "Re", "Mei", "Mi", "Fa", "Sei", "Sol", "Lei", "La", "Tei", "Ti"
    ];

    var pitchClass = note.pitch % 12; // 0 is C, 1 is C#/Db, etc.

    if (keySig === "sharp")
      return solfaNamesSharp[pitchClass];
    else if (keySig === "flat")
      return solfaNamesFlat[pitchClass];
    else
      return solfaNamesSharp[pitchClass]; // Default to sharp
  }

  function buildMeasureMap(score) {
    var map = {};
    var no = 1;
    var cursor = score.newCursor();
    cursor.rewind(Cursor.SCORE_START);
    while (cursor.measure) {
      var m = cursor.measure;
      var tick = m.firstSegment.tick;
      var tsD = m.timesigActual.denominator;
      var tsN = m.timesigActual.numerator;
      var ticksB = division * 4.0 / tsD;
      var ticksM = ticksB * tsN;
      no += m.noOffset;
      var cur = {
        "tick": tick,
        "tsD": tsD,
        "tsN": tsN,
        "ticksB": ticksB,
        "ticksM": ticksM,
        "past": (tick + ticksM),
        "no": no
      };
      map[cur.tick] = cur;
      console.log(tsN + "/" + tsD + " measure " + no +
        " at tick " + cur.tick + " length " + ticksM);
      if (!m.irregular)
        ++no;
      cursor.nextMeasure();
    }
    return map;
  }
  function showPos(cursor, measureMap) {
    var t = cursor.segment.tick;
    var m = measureMap[cursor.measure.firstSegment.tick];
    var b = "?";
    if (m && t >= m.tick && t < m.past) {
      b = 1 + (t - m.tick) / m.ticksB;
    }
    return "St" + (cursor.staffIdx + 1) +
      " Vc" + (cursor.voice + 1) +
      " Ms" + m.no + " Bt" + b;
  }
  /** signature: applyToSelectionOrScore(cb, ...args) */
  function applyToSelectionOrScore(cb) {
    var args = Array.prototype.slice.call(arguments, 1);
    var staveBeg;
    var staveEnd;
    var tickEnd;
    var rewindMode;
    var toEOF;
    var cursor = curScore.newCursor();
    cursor.rewind(Cursor.SELECTION_START);
    if (cursor.segment) {
      staveBeg = cursor.staffIdx;
      cursor.rewind(Cursor.SELECTION_END);
      staveEnd = cursor.staffIdx;
      if (!cursor.tick) {
        /*
         * This happens when the selection goes to the
         * end of the score — rewind() jumps behind the
         * last segment, setting tick = 0.
         */
        toEOF = true;
      } else {
        toEOF = false;
        tickEnd = cursor.tick;
      }
      rewindMode = Cursor.SELECTION_START;
    } else {
      /* no selection */
      staveBeg = 0;
      staveEnd = curScore.nstaves - 1;
      toEOF = true;
      rewindMode = Cursor.SCORE_START;
    }
    for (var stave = staveBeg; stave <= staveEnd; ++stave) {
      for (var voice = 0; voice < 4; ++voice) {
        cursor.staffIdx = stave;
        cursor.voice = voice;
        cursor.rewind(rewindMode);
        /*XXX https://musescore.org/en/node/301846 */
        cursor.staffIdx = stave;
        cursor.voice = voice;
        while (cursor.segment &&
          (toEOF || cursor.tick < tickEnd)) {
          if (cursor.element)
            cb.apply(null,
              [cursor].concat(args));
          cursor.next();
        }
      }
    }
  }
  function dropLyrics(cursor, measureMap) {
    if (!cursor.element.lyrics)
      return;
    for (var i = 0; i < cursor.element.lyrics.length; ++i) {
      console.log(showPos(cursor, measureMap) + ": Lyric#" +
        i + " = " + cursor.element.lyrics[i].text);
      /* removeElement was added in 3.3.0 */
      removeElement(cursor.element.lyrics[i]);
    }
  }

  function nameNotes(cursor, measureMap) {
    //console.log(showPos(cursor, measureMap) + ": " +
    //    nameElementType(cursor.element.type));
    var keySig = getKeySignature(cursor);
    if (cursor.element.type !== Element.CHORD)
      return;
    var text = newElement(Element.LYRICS);
    text.text = "";
    var notes = cursor.element.notes;
    var sep = "";
    for (var i = 0; i < notes.length; ++i) {
      text.text += sep + nameNote(notes[i], keySig);
      sep = "–";
    }
    if (text.text == "")
      return;
    text.verse = cursor.voice;
    //console.log(showPos(cursor, measureMap) + ": add verse(" +
    //    (text.verse + 1) + ")=" + text.text);
    cursor.element.add(text);
  }
  onRun: {
    curScore.startCmd()
    var measureMap = buildMeasureMap(curScore);
    if (removeElement)
      applyToSelectionOrScore(dropLyrics, measureMap);
    applyToSelectionOrScore(nameNotes, measureMap);
    curScore.endCmd()
  }
}
