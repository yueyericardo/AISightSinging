import MuseScore 3.0
import QtQuick 2.9
import FileIO 3.0

MuseScore {
  property string pname: "Add fixed Do solfa names as lyrics"
  menuPath: "Plugins." + pname
  version: "20231123B"
  id: pluginscope

  // =========== The following is a debug log file handler ===========
  Item {
    id: debugTools
      property string pluginName: "AddSolfaLyricsFixedDo"
      property string allLogMessages: "" // Variable to store log messages

      FileIO { // File handler for logging
      id: fileHandler
      source: ""
      onError: console.log(msg)
    }

    Component.onCompleted: { // Initialize log file on component load
      if (pluginName && pluginName !== "") {
        var logFilePath = fileHandler.homePath() + "/Documents/MuseScore4/Plugins/" + pluginName + "_log.txt";
        fileHandler.source = logFilePath;
        logMessage("Log started: " + getSystemDate());
      }
    }

    Component.onDestruction: { // Log when the component is unloaded
      logMessage("Log ended: " + getSystemDate());
      writeLogToFile()
    }

    function logMessage(message, writeToFile = true) {
      var fullMessage = getSystemDate() + " - " + message + "\n";
      allLogMessages += fullMessage
      if (writeToFile) {
        writeLogToFile();
      }
    }

    function writeLogToFile() {
      fileHandler.write(allLogMessages);
    }

    function getSystemDate() { // Helper function to get current date and time
      return Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss");
    }
  }
  // ==================================================================

  // Initialization when the plugin is loaded
  Component.onCompleted: {
    if (mscoreMajorVersion >= 4) {
      pluginscope.title = pluginscope.pname
    }
  }

  // Function to assign solfa names to notes
  function nameNote(note) {
    var solfaNames = ["Do", "Di", "Re", "Ri", "Mi", "Fa", "Fi", "Sol", "Si", "La", "Li", "Ti"]
    var pitchClass = note.pitch % 12  // 0 is C, 1 is C#/Db, etc.
    return solfaNames[pitchClass]
  }

  // Function to build a map of measures in the score
  function buildMeasureMap(score) {
    var map = {}
    var no = 1
    var cursor = score.newCursor()
    cursor.rewind(Cursor.SCORE_START)
    while (cursor.measure) {
      var m = cursor.measure;
      var tick = m.firstSegment.tick;
      var tsD = m.timesigActual.denominator;
      var tsN = m.timesigActual.numerator;
      var ticks_per_beat = division * 4.0 / tsD;
      var ticks_per_measure = ticks_per_beat * tsN;
      no += m.noOffset;
      var cur = {
        "tick": tick,
        "tsD": tsD,
        "tsN": tsN,
        "ticks_per_beat": ticks_per_beat,
        "ticks_per_measure": ticks_per_measure,
        "past": (tick + ticks_per_measure),
        "no": no
      };
      map[cur.tick] = cur;
      debugTools.logMessage(tsN + "/" + tsD + " measure " + no + " at tick " + cur.tick + " length " + ticks_per_measure + " ticks_per_beat " + ticks_per_beat);
      if (!m.irregular)
        ++no;
      cursor.nextMeasure();
    }
    return map
  }

  // Function to show cursor position in the score
  function showPos(cursor, measureMap) {
    // Logic to determine the position of the cursor
    var tick = cursor.segment.tick;
    var measure = measureMap[cursor.measure.firstSegment.tick];
    var beat = "?";
    if (measure && tick >= measure.tick && tick < measure.past) {
      beat = 1 + (tick - measure.tick) / measure.ticks_per_beat;
    }
    return "Staff" + (cursor.staffIdx + 1) + " Voice" + (cursor.voice + 1) + " Measure" + measure.no + " Beat" + beat;
  }

  // Function to apply a callback to the selection or entire score
  function applyToSelectionOrScore(callback) {
    // Logic to iterate over the selected part or the entire score
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
        * end of the score — rewind() jumps behind the
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
        while (cursor.segment && (toEOF || cursor.tick < tickEnd)) {
          if (cursor.element) {
            callback.apply(null, [cursor].concat(args));
          }
          cursor.next();
        }
      }
    }
  }

  // Function to remove existing lyrics
  function dropLyrics(cursor, measureMap) {
    if (!cursor.element.lyrics) return
    for (var i = 0; i < cursor.element.lyrics.length; ++i) {
      // debugTools.logMessage(showPos(cursor, measureMap) + ": Lyric#" + i + " = " + cursor.element.lyrics[i].text)
      removeElement(cursor.element.lyrics[i])
    }
  }

  // Function to name notes and add them as lyrics
  function nameNotes(cursor, measureMap) {
    if (cursor.element.type !== Element.CHORD) return
    var text = newElement(Element.LYRICS)
    text.text = ""
    var notes = cursor.element.notes
    var sep = ""
    for (var i = 0; i < notes.length; ++i) {
      text.text += sep + nameNote(notes[i])
      sep = "–"
    }
    if (text.text == "") return
    text.verse = cursor.voice
    cursor.element.add(text)
    debugTools.logMessage(showPos(cursor, measureMap) + ": Lyric#" + " = " + cursor.element.lyrics[0].text)
  }

  // Main execution function
  onRun: {
    curScore.startCmd()
    debugTools.logMessage("Starting " + pname + " plugin")
    var measureMap = buildMeasureMap(curScore)
    if (removeElement) {
      applyToSelectionOrScore(dropLyrics, measureMap)
    }
    applyToSelectionOrScore(nameNotes, measureMap)
    curScore.endCmd()
  }
}
