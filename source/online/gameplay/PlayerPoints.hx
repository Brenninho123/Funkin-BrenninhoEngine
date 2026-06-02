package online.gameplay;

import haxe.Json;
import haxe.crypto.Md5;
import sys.FileSystem;
import sys.io.File;

typedef PointsEntry =
{
	var songName:String;
	var difficulty:String;
	var score:Int;
	var misses:Int;
	var hits:Int;
	var combo:Int;
	var rating:Float;
	var ratingName:String;
	var ratingFC:String;
	var platform:String;
	var timestamp:Float;
}

typedef PlayerStats =
{
	var totalScore:Int;
	var totalMisses:Int;
	var totalHits:Int;
	var totalPlays:Int;
	var bestCombo:Int;
	var bestRating:Float;
	var averageRating:Float;
	var rank:String;
	var level:Int;
	var xp:Int;
	var xpToNextLevel:Int;
}

typedef PointsSnapshot =
{
	var username:String;
	var stats:PlayerStats;
	var history:Array<PointsEntry>;
	var checksum:String;
	var savedAt:Float;
}

class PlayerPoints
{
	static final SAVE_FILE:String       = "saves/player_points.json";
	static final CLOUD_KEY:String       = "player_points.json";
	static final XP_PER_HIT:Int         = 2;
	static final XP_PER_MISS_PENALTY:Int = 1;
	static final XP_SCORE_DIVIDER:Int   = 100;
	static final XP_FC_BONUS:Int        = 50;
	static final XP_PERFECT_BONUS:Int   = 100;
	static final BASE_XP_PER_LEVEL:Int  = 500;
	static final XP_LEVEL_SCALE:Float   = 1.2;
	static final MAX_HISTORY:Int        = 100;

	static final RANKS:Array<String> = [
		'Beginner', 'Novice', 'Apprentice', 'Skilled',
		'Proficient', 'Expert', 'Master', 'Grandmaster', 'Legend'
	];

	public static var isInitialized:Bool    = false;
	public static var currentStats:PlayerStats = null;
	public static var onLevelUp:Int->Void   = null;
	public static var onRankUp:String->Void = null;
	public static var onPointsEarned:Int->Void = null;

	private static var _history:Array<PointsEntry> = [];
	private static var _username:String             = 'Player';
	private static var _dirty:Bool                  = false;

	public static function init(?username:String = 'Player'):Void
	{
		if (isInitialized) return;

		_username     = username;
		isInitialized = true;

		_load();

		if (currentStats == null)
			currentStats = _defaultStats();
	}

	public static function submitScore(
		songName:String,
		difficulty:String,
		score:Int,
		misses:Int,
		hits:Int,
		combo:Int,
		rating:Float,
		ratingName:String,
		ratingFC:String
	):Void
	{
		if (!isInitialized) init();

		var entry:PointsEntry = {
			songName:   songName,
			difficulty: difficulty,
			score:      score,
			misses:     misses,
			hits:       hits,
			combo:      combo,
			rating:     rating,
			ratingName: ratingName,
			ratingFC:   ratingFC,
			platform:   backend.system.Main.platform,
			timestamp:  Date.now().getTime()
		};

		_history.unshift(entry);
		if (_history.length > MAX_HISTORY)
			_history.pop();

		var earned:Int = _calculateXP(entry);
		_applyXP(earned, entry);
		_updateStats(entry);

		_dirty = true;
		save();

		if (onPointsEarned != null) onPointsEarned(earned);

		if (online.Online.isConnected)
			_syncToCloud();
	}

	public static function getHistory(?limit:Int = 20):Array<PointsEntry>
	{
		return _history.slice(0, Std.int(Math.min(limit, _history.length)));
	}

	public static function getHistoryBySong(songName:String):Array<PointsEntry>
	{
		return _history.filter((e:PointsEntry) -> e.songName.toLowerCase() == songName.toLowerCase());
	}

	public static function getBestScore(songName:String, ?difficulty:String):Null<PointsEntry>
	{
		var entries:Array<PointsEntry> = _history.filter((e:PointsEntry) ->
		{
			var match:Bool = e.songName.toLowerCase() == songName.toLowerCase();
			if (difficulty != null)
				match = match && e.difficulty.toLowerCase() == difficulty.toLowerCase();
			return match;
		});

		if (entries.length == 0) return null;

		entries.sort((a:PointsEntry, b:PointsEntry) -> b.score - a.score);
		return entries[0];
	}

	public static function getTopScores(?limit:Int = 10):Array<PointsEntry>
	{
		var sorted:Array<PointsEntry> = _history.copy();
		sorted.sort((a:PointsEntry, b:PointsEntry) -> b.score - a.score);
		return sorted.slice(0, limit);
	}

	public static function getTotalXP():Int
	{
		return currentStats != null ? currentStats.xp : 0;
	}

	public static function getLevel():Int
	{
		return currentStats != null ? currentStats.level : 1;
	}

	public static function getRank():String
	{
		return currentStats != null ? currentStats.rank : RANKS[0];
	}

	public static function getXPProgress():Float
	{
		if (currentStats == null) return 0;
		var needed:Int = currentStats.xpToNextLevel;
		if (needed <= 0) return 1.0;
		var current:Int = currentStats.xp - _xpForLevel(currentStats.level);
		return FlxMath.bound(current / needed, 0.0, 1.0);
	}

	public static function getLevelProgressText():String
	{
		if (currentStats == null) return 'Lv.1 — 0 / 500 XP';
		var current:Int = currentStats.xp - _xpForLevel(currentStats.level);
		return 'Lv.${currentStats.level} — $current / ${currentStats.xpToNextLevel} XP';
	}

	public static function getFormattedStats():String
	{
		if (currentStats == null) return '';
		return [
			'Rank: ${currentStats.rank}',
			'Level: ${currentStats.level}',
			'XP: ${currentStats.xp}',
			'Total Score: ${currentStats.totalScore}',
			'Total Plays: ${currentStats.totalPlays}',
			'Best Combo: ${currentStats.bestCombo}',
			'Best Rating: ${Math.round(currentStats.bestRating * 100)}%',
			'Average Rating: ${Math.round(currentStats.averageRating * 100)}%'
		].join('\n');
	}

	public static function resetProgress():Void
	{
		_history     = [];
		currentStats = _defaultStats();
		_dirty       = true;
		save();
	}

	public static function save():Void
	{
		if (!_dirty) return;

		try
		{
			if (!FileSystem.exists('saves'))
				FileSystem.createDirectory('saves');

			var snapshot:PointsSnapshot = _buildSnapshot();
			File.saveContent(SAVE_FILE, Json.stringify(snapshot));
			_dirty = false;
		}
		catch (e:Dynamic) {}
	}

	private static function _load():Void
	{
		if (!FileSystem.exists(SAVE_FILE)) return;

		try
		{
			var content:String      = File.getContent(SAVE_FILE);
			var parsed:Dynamic      = Json.parse(content);
			var checksum:String     = Reflect.field(parsed, 'checksum');
			var dataStr:String      = Json.stringify({
				username: Reflect.field(parsed, 'username'),
				stats:    Reflect.field(parsed, 'stats'),
				history:  Reflect.field(parsed, 'history'),
				savedAt:  Reflect.field(parsed, 'savedAt')
			});

			if (Md5.encode(dataStr) != checksum)
			{
				currentStats = _defaultStats();
				_history     = [];
				return;
			}

			currentStats = _parseStats(Reflect.field(parsed, 'stats'));
			_username    = Reflect.field(parsed, 'username');

			var rawHistory:Array<Dynamic> = Reflect.field(parsed, 'history');
			_history = rawHistory.map((e:Dynamic) -> _parseEntry(e));
		}
		catch (e:Dynamic)
		{
			currentStats = _defaultStats();
			_history     = [];
		}
	}

	private static function _syncToCloud():Void
	{
		online.Online.uploadSave(CLOUD_KEY, null, null);
	}

	private static function _calculateXP(entry:PointsEntry):Int
	{
		var xp:Int = 0;

		xp += entry.hits  * XP_PER_HIT;
		xp -= entry.misses * XP_PER_MISS_PENALTY;
		xp += Std.int(entry.score / XP_SCORE_DIVIDER);

		if (entry.ratingFC == 'FC')     xp += XP_FC_BONUS;
		if (entry.ratingFC == 'PFC')    xp += XP_PERFECT_BONUS;
		if (entry.ratingFC == 'SDCB')   xp += Std.int(XP_FC_BONUS * 0.5);

		var diffMultiplier:Float = switch (entry.difficulty.toLowerCase()) {
			case 'easy':   0.7;
			case 'normal': 1.0;
			case 'hard':   1.3;
			case 'expert' | 'insane': 1.6;
			default: 1.0;
		};

		xp = Std.int(xp * diffMultiplier);
		return Std.int(Math.max(xp, 1));
	}

	private static function _applyXP(amount:Int, entry:PointsEntry):Void
	{
		var prevLevel:Int  = currentStats.level;
		var prevRank:String = currentStats.rank;

		currentStats.xp += amount;

		while (currentStats.xp >= _xpForLevel(currentStats.level + 1))
		{
			currentStats.level++;
			currentStats.xpToNextLevel = _xpForNextLevel(currentStats.level);

			if (onLevelUp != null) onLevelUp(currentStats.level);
		}

		currentStats.xpToNextLevel = _xpForNextLevel(currentStats.level);

		var newRank:String = _getRankForLevel(currentStats.level);
		if (newRank != prevRank)
		{
			currentStats.rank = newRank;
			if (onRankUp != null) onRankUp(newRank);
		}
	}

	private static function _updateStats(entry:PointsEntry):Void
	{
		currentStats.totalScore  += entry.score;
		currentStats.totalMisses += entry.misses;
		currentStats.totalHits   += entry.hits;
		currentStats.totalPlays++;

		if (entry.combo > currentStats.bestCombo)
			currentStats.bestCombo = entry.combo;

		if (entry.rating > currentStats.bestRating)
			currentStats.bestRating = entry.rating;

		var totalRating:Float = currentStats.averageRating * (currentStats.totalPlays - 1) + entry.rating;
		currentStats.averageRating = totalRating / currentStats.totalPlays;
	}

	private static function _xpForLevel(level:Int):Int
	{
		if (level <= 1) return 0;
		return Std.int(BASE_XP_PER_LEVEL * Math.pow(XP_LEVEL_SCALE, level - 1));
	}

	private static function _xpForNextLevel(level:Int):Int
	{
		return _xpForLevel(level + 1) - _xpForLevel(level);
	}

	private static function _getRankForLevel(level:Int):String
	{
		var index:Int = Std.int(FlxMath.bound(
			Math.floor((level - 1) / 5),
			0,
			RANKS.length - 1
		));
		return RANKS[index];
	}

	private static function _defaultStats():PlayerStats
	{
		return {
			totalScore:    0,
			totalMisses:   0,
			totalHits:     0,
			totalPlays:    0,
			bestCombo:     0,
			bestRating:    0.0,
			averageRating: 0.0,
			rank:          RANKS[0],
			level:         1,
			xp:            0,
			xpToNextLevel: BASE_XP_PER_LEVEL
		};
	}

	private static function _buildSnapshot():PointsSnapshot
	{
		var dataObj:Dynamic = {
			username: _username,
			stats:    currentStats,
			history:  _history,
			savedAt:  Date.now().getTime()
		};
		var dataStr:String  = Json.stringify(dataObj);
		var checksum:String = Md5.encode(dataStr);

		return {
			username: _username,
			stats:    currentStats,
			history:  _history,
			checksum: checksum,
			savedAt:  dataObj.savedAt
		};
	}

	private static function _parseStats(raw:Dynamic):PlayerStats
	{
		return {
			totalScore:    Reflect.field(raw, 'totalScore')    ?? 0,
			totalMisses:   Reflect.field(raw, 'totalMisses')   ?? 0,
			totalHits:     Reflect.field(raw, 'totalHits')     ?? 0,
			totalPlays:    Reflect.field(raw, 'totalPlays')    ?? 0,
			bestCombo:     Reflect.field(raw, 'bestCombo')     ?? 0,
			bestRating:    Reflect.field(raw, 'bestRating')    ?? 0.0,
			averageRating: Reflect.field(raw, 'averageRating') ?? 0.0,
			rank:          Reflect.field(raw, 'rank')          ?? RANKS[0],
			level:         Reflect.field(raw, 'level')         ?? 1,
			xp:            Reflect.field(raw, 'xp')            ?? 0,
			xpToNextLevel: Reflect.field(raw, 'xpToNextLevel') ?? BASE_XP_PER_LEVEL
		};
	}

	private static function _parseEntry(raw:Dynamic):PointsEntry
	{
		return {
			songName:   Reflect.field(raw, 'songName')   ?? '',
			difficulty: Reflect.field(raw, 'difficulty') ?? '',
			score:      Reflect.field(raw, 'score')      ?? 0,
			misses:     Reflect.field(raw, 'misses')     ?? 0,
			hits:       Reflect.field(raw, 'hits')       ?? 0,
			combo:      Reflect.field(raw, 'combo')      ?? 0,
			rating:     Reflect.field(raw, 'rating')     ?? 0.0,
			ratingName: Reflect.field(raw, 'ratingName') ?? '',
			ratingFC:   Reflect.field(raw, 'ratingFC')   ?? '',
			platform:   Reflect.field(raw, 'platform')   ?? '',
			timestamp:  Reflect.field(raw, 'timestamp')  ?? 0.0
		};
	}
}
