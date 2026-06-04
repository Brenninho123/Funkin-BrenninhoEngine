package backend;

import backend.Song;
import backend.Section;
import objects.Note;

typedef BPMChangeEvent =
{
	var stepTime:Int;
	var songTime:Float;
	var bpm:Float;
	@:optional var stepCrochet:Float;
}

class Conductor
{
	public static var bpm(default, set):Float = 100;
	public static var crochet:Float           = (60 / bpm) * 1000;
	public static var stepCrochet:Float       = crochet / 4;
	public static var songPosition:Float      = 0;
	public static var offset:Float            = 0;
	public static var safeZoneOffset:Float    = 0;

	public static var bpmChangeMap:Array<BPMChangeEvent> = [];

	public static function judgeNote(arr:Array<Rating>, diff:Float = 0):Rating
	{
		for (i in 0...arr.length - 1)
			if (diff <= arr[i].hitWindow)
				return arr[i];

		return arr[arr.length - 1];
	}

	public static function getCrochetAtTime(time:Float):Float
	{
		return getBPMFromSeconds(time).stepCrochet * 4;
	}

	public static function getBPMFromSeconds(time:Float):BPMChangeEvent
	{
		var lastChange:BPMChangeEvent = _defaultChange();

		for (change in bpmChangeMap)
			if (time >= change.songTime)
				lastChange = change;

		return lastChange;
	}

	public static function getBPMFromStep(step:Float):BPMChangeEvent
	{
		var lastChange:BPMChangeEvent = _defaultChange();

		for (change in bpmChangeMap)
			if (change.stepTime <= step)
				lastChange = change;

		return lastChange;
	}

	public static function beatToSeconds(beat:Float):Float
	{
		var step:Float            = beat * 4;
		var lastChange:BPMChangeEvent = getBPMFromStep(step);
		return lastChange.songTime + ((step - lastChange.stepTime) / (lastChange.bpm / 60) / 4) * 1000;
	}

	public static function getStep(time:Float):Float
	{
		var lastChange:BPMChangeEvent = getBPMFromSeconds(time);
		return lastChange.stepTime + (time - lastChange.songTime) / lastChange.stepCrochet;
	}

	public static function getStepRounded(time:Float):Float
	{
		var lastChange:BPMChangeEvent = getBPMFromSeconds(time);
		return lastChange.stepTime + Math.floor(time - lastChange.songTime) / lastChange.stepCrochet;
	}

	public static function getBeat(time:Float):Float
	{
		return getStep(time) / 4;
	}

	public static function getBeatRounded(time:Float):Int
	{
		return Math.floor(getStepRounded(time) / 4);
	}

	public static function getStepFromBeat(beat:Float):Float
	{
		return beat * 4;
	}

	public static function getTimeFromStep(step:Float):Float
	{
		var lastChange:BPMChangeEvent = getBPMFromStep(step);
		return lastChange.songTime + (step - lastChange.stepTime) * lastChange.stepCrochet;
	}

	public static function getTimeFromBeat(beat:Float):Float
	{
		return getTimeFromStep(beat * 4);
	}

	public static function mapBPMChanges(song:SwagSong):Void
	{
		bpmChangeMap = [];

		var curBPM:Float    = song.bpm;
		var totalSteps:Int  = 0;
		var totalPos:Float  = 0;

		for (i in 0...song.notes.length)
		{
			if (song.notes[i].changeBPM && song.notes[i].bpm != curBPM)
			{
				curBPM = song.notes[i].bpm;
				bpmChangeMap.push({
					stepTime:   totalSteps,
					songTime:   totalPos,
					bpm:        curBPM,
					stepCrochet: calculateCrochet(curBPM) / 4
				});
			}

			var deltaSteps:Int = Math.round(_getSectionBeats(song, i) * 4);
			totalSteps        += deltaSteps;
			totalPos          += ((60 / curBPM) * 1000 / 4) * deltaSteps;
		}
	}

	public static function getCurrentBPM():Float
	{
		return getBPMFromSeconds(songPosition).bpm;
	}

	public static function getCurrentStep():Float
	{
		return getStep(songPosition);
	}

	public static function getCurrentBeat():Float
	{
		return getBeat(songPosition);
	}

	public static function isOnBeat(?tolerance:Float = 50):Bool
	{
		var beatTime:Float = getBeat(songPosition);
		var nearest:Float  = Math.round(beatTime) * (crochet);
		return Math.abs(songPosition - nearest) <= tolerance;
	}

	inline public static function calculateCrochet(bpm:Float):Float
	{
		return (60 / bpm) * 1000;
	}

	public static function set_bpm(newBPM:Float):Float
	{
		bpm         = newBPM;
		crochet     = calculateCrochet(bpm);
		stepCrochet = crochet / 4;
		return bpm;
	}

	private static function _defaultChange():BPMChangeEvent
	{
		return {
			stepTime:    0,
			songTime:    0,
			bpm:         bpm,
			stepCrochet: stepCrochet
		};
	}

	private static function _getSectionBeats(song:SwagSong, section:Int):Float
	{
		var val:Null<Float> = song.notes[section] != null ? song.notes[section].sectionBeats : null;
		return val != null ? val : 4;
	}
}