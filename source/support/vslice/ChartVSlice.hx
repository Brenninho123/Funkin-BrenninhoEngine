package support.vslice;

import haxe.Json;

typedef VSliceNote =
{
	var t:Float;
	var d:Int;
	@:optional var l:Float;
	@:optional var k:String;
}

typedef VSliceEvent =
{
	var t:Float;
	var e:String;
	var v:Dynamic;
}

typedef VSliceScrollSpeeds =
{
	@:optional var normal:Float;
	@:optional var hard:Float;
	@:optional var easy:Float;
}

typedef VSliceNotesByDiff =
{
	@:optional var normal:Array<VSliceNote>;
	@:optional var hard:Array<VSliceNote>;
	@:optional var easy:Array<VSliceNote>;
}

typedef VSliceChart =
{
	var version:String;
	var scrollSpeed:VSliceScrollSpeeds;
	var events:Array<VSliceEvent>;
	var notes:VSliceNotesByDiff;
	@:optional var generatedBy:String;
}

typedef VSliceConvertedNote =
{
	var time:Float;
	var data:Int;
	var length:Float;
	var isPlayer:Bool;
	var noteType:String;
}

typedef VSliceConvertedEvent =
{
	var time:Float;
	var name:String;
	var params:Dynamic;
}

typedef VSliceConvertedChart =
{
	var notes:Array<VSliceConvertedNote>;
	var events:Array<VSliceConvertedEvent>;
	var scrollSpeed:Float;
	var bpm:Float;
	var valid:Bool;
}

class ChartVSlice
{
	static final PLAYER_LANE_MIN:Int  = 4;
	static final PLAYER_LANE_MAX:Int  = 7;
	static final OPPONENT_LANE_MIN:Int = 0;
	static final OPPONENT_LANE_MAX:Int = 3;

	public static function load(path:String, ?difficulty:String = 'normal'):Null<VSliceConvertedChart>
	{
		#if sys
		if (!sys.FileSystem.exists(path)) return null;
		try
		{
			var content:String = sys.io.File.getContent(path);
			return parse(content, difficulty);
		}
		catch (e:Dynamic) { return null; }
		#else
		var content:String = openfl.Assets.getText(path);
		if (content == null) return null;
		try { return parse(content, difficulty); }
		catch (e:Dynamic) { return null; }
		#end
	}

	public static function parse(jsonContent:String, ?difficulty:String = 'normal'):Null<VSliceConvertedChart>
	{
		if (jsonContent == null || jsonContent.length == 0) return null;

		try
		{
			var raw:Dynamic      = Json.parse(jsonContent);
			var chart:VSliceChart = cast raw;

			if (chart == null || chart.notes == null) return null;

			var rawNotes:Array<VSliceNote> = _getNotesForDiff(chart, difficulty);
			if (rawNotes == null) rawNotes = [];

			var converted:VSliceConvertedChart = {
				notes:       _convertNotes(rawNotes),
				events:      _convertEvents(chart.events ?? []),
				scrollSpeed: _getScrollSpeed(chart, difficulty),
				bpm:         _guessBPM(rawNotes),
				valid:       true
			};

			return converted;
		}
		catch (e:Dynamic) { return null; }
	}

	public static function isVSliceChart(jsonContent:String):Bool
	{
		if (jsonContent == null) return false;
		try
		{
			var raw:Dynamic = Json.parse(jsonContent);
			return Reflect.field(raw, 'version') != null
				&& Reflect.field(raw, 'scrollSpeed') != null
				&& Reflect.field(raw, 'notes') != null
				&& Reflect.field(raw, 'events') != null;
		}
		catch (e:Dynamic) { return false; }
	}

	public static function isVSliceFile(path:String):Bool
	{
		#if sys
		if (!sys.FileSystem.exists(path)) return false;
		try { return isVSliceChart(sys.io.File.getContent(path)); }
		catch (e:Dynamic) { return false; }
		#else
		var content:String = openfl.Assets.getText(path);
		return content != null && isVSliceChart(content);
		#end
	}

	public static function getAvailableDifficulties(jsonContent:String):Array<String>
	{
		var result:Array<String> = [];
		try
		{
			var raw:Dynamic   = Json.parse(jsonContent);
			var notes:Dynamic = Reflect.field(raw, 'notes');
			if (notes == null) return result;
			for (field in Reflect.fields(notes))
				result.push(field);
		}
		catch (e:Dynamic) {}
		return result;
	}

	public static function getScrollSpeed(jsonContent:String, ?difficulty:String = 'normal'):Float
	{
		try
		{
			var raw:Dynamic     = Json.parse(jsonContent);
			var chart:VSliceChart = cast raw;
			return _getScrollSpeed(chart, difficulty);
		}
		catch (e:Dynamic) { return 1.0; }
	}

	public static function getNoteCount(jsonContent:String, ?difficulty:String = 'normal'):Int
	{
		try
		{
			var raw:Dynamic       = Json.parse(jsonContent);
			var chart:VSliceChart  = cast raw;
			var notes:Array<VSliceNote> = _getNotesForDiff(chart, difficulty);
			if (notes == null) return 0;
			return notes.filter((n:VSliceNote) -> n.l == null || n.l == 0).length;
		}
		catch (e:Dynamic) { return 0; }
	}

	public static function getEventsByName(converted:VSliceConvertedChart, name:String):Array<VSliceConvertedEvent>
	{
		return converted.events.filter((e:VSliceConvertedEvent) -> e.name == name);
	}

	public static function getPlayerNotes(converted:VSliceConvertedChart):Array<VSliceConvertedNote>
	{
		return converted.notes.filter((n:VSliceConvertedNote) -> n.isPlayer);
	}

	public static function getOpponentNotes(converted:VSliceConvertedChart):Array<VSliceConvertedNote>
	{
		return converted.notes.filter((n:VSliceConvertedNote) -> !n.isPlayer);
	}

	public static function toPsychFormat(converted:VSliceConvertedChart, ?songName:String = 'unknown', ?bpm:Float = 110):Dynamic
	{
		if (converted == null || !converted.valid) return null;

		var sectionDuration:Float = (60 / bpm) * 4 * 1000;
		var sectionsMap:Map<Int, Array<Dynamic>> = new Map();

		for (note in converted.notes)
		{
			var sectionIdx:Int    = Math.floor(note.time / sectionDuration);
			var psychData:Int     = note.isPlayer ? (note.data % 4) + 4 : note.data % 4;

			if (!sectionsMap.exists(sectionIdx))
				sectionsMap.set(sectionIdx, []);

			sectionsMap.get(sectionIdx).push([note.time, psychData, note.length, note.noteType]);
		}

		var sections:Array<Dynamic> = [];
		var maxSection:Int          = 0;
		for (idx in sectionsMap.keys())
			if (idx > maxSection) maxSection = idx;

		for (i in 0...maxSection + 1)
		{
			var sectionNotes:Array<Dynamic> = sectionsMap.exists(i) ? sectionsMap.get(i) : [];
			var mustHit:Bool = sectionNotes.filter((n:Array<Dynamic>) -> {
				var d:Int = Std.int(n[1]);
				return d >= 4 && d <= 7;
			}).length >= sectionNotes.length / 2;

			sections.push({
				sectionNotes: sectionNotes,
				mustHitSection: mustHit,
				bpm:            bpm,
				changeBPM:      false,
				altAnim:        false,
				gfSection:      false,
				sectionBeats:   4
			});
		}

		return {
			song: {
				song:        songName,
				notes:       sections,
				bpm:         bpm,
				speed:       converted.scrollSpeed,
				player1:     'bf',
				player2:     'dad',
				gfVersion:   'gf',
				stage:       'stage',
				needsVoices: true,
				events:      _convertEventsToPsych(converted.events)
			}
		};
	}

	private static function _convertNotes(rawNotes:Array<VSliceNote>):Array<VSliceConvertedNote>
	{
		var result:Array<VSliceConvertedNote> = [];

		for (n in rawNotes)
		{
			if (n == null) continue;

			var lane:Int     = n.d;
			var isPlayer:Bool = lane >= PLAYER_LANE_MIN && lane <= PLAYER_LANE_MAX;
			var data:Int     = lane % 4;

			result.push({
				time:     n.t,
				data:     data,
				length:   n.l ?? 0,
				isPlayer: isPlayer,
				noteType: n.k ?? ''
			});
		}

		result.sort((a:VSliceConvertedNote, b:VSliceConvertedNote) ->
			a.time < b.time ? -1 : a.time > b.time ? 1 : 0
		);

		return result;
	}

	private static function _convertEvents(rawEvents:Array<VSliceEvent>):Array<VSliceConvertedEvent>
	{
		if (rawEvents == null) return [];

		var result:Array<VSliceConvertedEvent> = [];

		for (e in rawEvents)
		{
			if (e == null) continue;
			result.push({
				time:   e.t,
				name:   e.e,
				params: e.v
			});
		}

		result.sort((a:VSliceConvertedEvent, b:VSliceConvertedEvent) ->
			a.time < b.time ? -1 : a.time > b.time ? 1 : 0
		);

		return result;
	}

	private static function _convertEventsToPsych(events:Array<VSliceConvertedEvent>):Array<Dynamic>
	{
		var result:Array<Dynamic> = [];

		for (e in events)
		{
			var value1:String = '';
			var value2:String = '';

			if (e.params != null)
			{
				var fields:Array<String> = Reflect.fields(e.params);
				if (fields.length > 0) value1 = Std.string(Reflect.field(e.params, fields[0]));
				if (fields.length > 1) value2 = Std.string(Reflect.field(e.params, fields[1]));
			}

			result.push([e.time, [[e.name, value1, value2]]]);
		}

		return result;
	}

	private static function _getNotesForDiff(chart:VSliceChart, difficulty:String):Array<VSliceNote>
	{
		var notes:Dynamic = chart.notes;
		if (notes == null) return [];

		var result:Dynamic = Reflect.field(notes, difficulty);
		if (result == null) result = Reflect.field(notes, 'normal');
		if (result == null)
		{
			var fields:Array<String> = Reflect.fields(notes);
			if (fields.length > 0) result = Reflect.field(notes, fields[0]);
		}

		if (result == null) return [];

		var raw:Array<Dynamic> = cast result;
		return raw.map((n:Dynamic) ->
		{
			var note:VSliceNote = { t: 0, d: 0 };
			note.t = Reflect.field(n, 't') ?? 0;
			note.d = Reflect.field(n, 'd') ?? 0;
			var l:Dynamic = Reflect.field(n, 'l');
			if (l != null) note.l = l;
			var k:Dynamic = Reflect.field(n, 'k');
			if (k != null) note.k = k;
			return note;
		});
	}

	private static function _getScrollSpeed(chart:VSliceChart, difficulty:String):Float
	{
		if (chart.scrollSpeed == null) return 1.0;
		var speeds:Dynamic = chart.scrollSpeed;
		var val:Dynamic    = Reflect.field(speeds, difficulty);
		if (val == null)   val = Reflect.field(speeds, 'normal');
		if (val == null)
		{
			var fields:Array<String> = Reflect.fields(speeds);
			if (fields.length > 0) val = Reflect.field(speeds, fields[0]);
		}
		return val != null ? val : 1.0;
	}

	private static function _guessBPM(notes:Array<VSliceNote>):Float
	{
		if (notes == null || notes.length < 4) return 110.0;

		var gaps:Array<Float> = [];
		var nonSustain:Array<Float> = notes
			.filter((n:VSliceNote) -> n.l == null || n.l == 0)
			.map((n:VSliceNote) -> n.t);

		nonSustain.sort((a:Float, b:Float) -> a < b ? -1 : 1);

		var limit:Int = Std.int(Math.min(nonSustain.length - 1, 16));
		for (i in 0...limit)
			gaps.push(nonSustain[i + 1] - nonSustain[i]);

		gaps = gaps.filter((g:Float) -> g > 50 && g < 2000);
		if (gaps.length == 0) return 110.0;

		var avg:Float = 0;
		for (g in gaps) avg += g;
		avg /= gaps.length;

		return FlxMath.bound(60000 / avg, 60, 300);
	}
}
