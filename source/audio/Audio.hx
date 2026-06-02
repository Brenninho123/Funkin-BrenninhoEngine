package audio;

import flixel.sound.FlxSound;
import flixel.math.FlxMath;

typedef AudioEffect =
{
	var name:String;
	var intensity:Float;
	var enabled:Bool;
}

typedef AudioSnapshot =
{
	var musicVolume:Float;
	var sfxVolume:Float;
	var masterVolume:Float;
	var pitch:Float;
	var timestamp:Float;
}

typedef AudioTrack =
{
	var sound:FlxSound;
	var key:String;
	var category:String;
	var baseVolume:Float;
}

class Audio
{
	static final FADE_MIN_VOLUME:Float      = 0.0001;
	static final COMPRESSOR_THRESHOLD:Float = 0.8;
	static final COMPRESSOR_RATIO:Float     = 0.6;
	static final BASS_BOOST_MAX:Float       = 0.3;
	static final DUCKING_AMOUNT:Float       = 0.45;
	static final DUCKING_LERP:Float         = 6.0;
	static final DUCK_RESTORE_TIME:Float    = 0.3;
	static final MAX_TRACKED:Int            = 64;

	public static var masterVolume(default, set):Float = 1.0;
	public static var musicVolume(default, set):Float  = 1.0;
	public static var sfxVolume(default, set):Float    = 1.0;
	public static var uiVolume(default, set):Float     = 1.0;

	public static var isInitialized:Bool            = false;
	public static var onBeat:Int->Void              = null;
	public static var onVolumeChanged:Float->Void   = null;
	public static var onMusicEnd:Void->Void         = null;
	public static var onSoundFinished:String->Void  = null;

	private static var _effects:Map<String, AudioEffect>  = new Map();
	private static var _snapshots:Array<AudioSnapshot>    = [];
	private static var _tracks:Array<AudioTrack>          = [];
	private static var _duckedTracks:Array<AudioTrack>    = [];
	private static var _isDucking:Bool                    = false;
	private static var _duckTimer:Float                   = 0.0;
	private static var _duckDuration:Float                = 0.0;
	private static var _compressorEnabled:Bool            = false;
	private static var _bassBoost:Float                   = 0.0;
	private static var _pitch:Float                       = 1.0;
	private static var _crossfadeActive:Bool              = false;
	private static var _beatCount:Int                     = 0;
	private static var _lowPassEnabled:Bool               = false;
	private static var _lowPassIntensity:Float            = 0.5;
	private static var _globalPan:Float                   = 0.0;

	public static function init():Void
	{
		if (isInitialized) return;

		isInitialized = true;
		masterVolume  = 1.0;
		musicVolume   = 1.0;
		sfxVolume     = 1.0;
		uiVolume      = 1.0;

		_registerDefaultEffects();
	}

	public static function update(elapsed:Float):Void
	{
		if (!isInitialized) return;

		if (_isDucking)
		{
			_duckTimer += elapsed;

			for (track in _duckedTracks)
			{
				if (track.sound == null || !track.sound.alive) continue;
				var target:Float = track.baseVolume * (1.0 - DUCKING_AMOUNT);
				track.sound.volume = FlxMath.lerp(track.sound.volume, target, DUCKING_LERP * elapsed);
			}

			if (_duckDuration > 0 && _duckTimer >= _duckDuration)
				unduck();
		}

		if (_compressorEnabled && FlxG.sound.music != null && FlxG.sound.music.playing)
			_applyCompressor();

		_cleanTracks();
	}

	public static function playMusic(key:String, ?volume:Float = 1.0, ?loop:Bool = true, ?fadeDuration:Float = 0.0, ?category:String = 'music'):Void
	{
		var targetVolume:Float = FlxMath.bound(volume * musicVolume * masterVolume, 0.0, 1.0);

		if (fadeDuration > 0 && FlxG.sound.music != null && FlxG.sound.music.playing)
		{
			fadeOut(FlxG.sound.music, fadeDuration * 0.5, function():Void
			{
				FlxG.sound.playMusic(Paths.music(key), 0, loop);
				_applyPitchToMusic();
				fadeIn(FlxG.sound.music, fadeDuration * 0.5, targetVolume);
			});
		}
		else
		{
			FlxG.sound.playMusic(Paths.music(key), fadeDuration > 0 ? 0 : targetVolume, loop);
			_applyPitchToMusic();
			if (fadeDuration > 0)
				fadeIn(FlxG.sound.music, fadeDuration, targetVolume);
		}

		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.onComplete = function():Void
			{
				if (onMusicEnd != null) onMusicEnd();
			};
		}

		if (_lowPassEnabled) _applyLowPassToMusic();
		if (_globalPan != 0) _applyPanToSound(FlxG.sound.music, _globalPan);
	}

	public static function playSound(key:String, ?volume:Float = 1.0, ?loop:Bool = false, ?category:String = 'sfx'):FlxSound
	{
		var catVolume:Float   = category == 'ui' ? uiVolume : sfxVolume;
		var finalVolume:Float = FlxMath.bound(volume * catVolume * masterVolume, 0.0, 1.0);
		var sound:FlxSound    = FlxG.sound.play(Paths.sound(key), finalVolume, loop);

		if (sound != null)
		{
			_applyPitchToSound(sound);
			if (_globalPan != 0) _applyPanToSound(sound, _globalPan);

			var track:AudioTrack = {
				sound:      sound,
				key:        key,
				category:   category,
				baseVolume: finalVolume
			};
			_tracks.push(track);

			if (_tracks.length > MAX_TRACKED)
				_tracks.shift();

			sound.onComplete = function():Void
			{
				if (onSoundFinished != null) onSoundFinished(key);
				_tracks = _tracks.filter((t:AudioTrack) -> t.sound != sound);
			};
		}

		return sound;
	}

	public static function playUI(key:String, ?volume:Float = 1.0):FlxSound
	{
		return playSound(key, volume, false, 'ui');
	}

	public static function fadeIn(sound:FlxSound, duration:Float, ?targetVolume:Float = 1.0, ?onComplete:Void->Void):Void
	{
		if (sound == null) return;

		sound.volume = FADE_MIN_VOLUME;
		FlxTween.tween(sound, {volume: FlxMath.bound(targetVolume * masterVolume, 0.0, 1.0)}, duration, {
			ease: FlxEase.quartOut,
			onComplete: function(_:FlxTween):Void
			{
				if (onComplete != null) onComplete();
			}
		});
	}

	public static function fadeOut(sound:FlxSound, duration:Float, ?onComplete:Void->Void):Void
	{
		if (sound == null) return;

		FlxTween.tween(sound, {volume: FADE_MIN_VOLUME}, duration, {
			ease: FlxEase.quartIn,
			onComplete: function(_:FlxTween):Void
			{
				sound.stop();
				if (onComplete != null) onComplete();
			}
		});
	}

	public static function crossfade(fromSound:FlxSound, toKey:String, duration:Float, ?loop:Bool = true):Void
	{
		if (_crossfadeActive) return;
		_crossfadeActive = true;

		var toSound:FlxSound = FlxG.sound.play(Paths.music(toKey), FADE_MIN_VOLUME, loop);
		if (toSound == null) { _crossfadeActive = false; return; }

		_applyPitchToSound(toSound);

		var targetVolume:Float = FlxMath.bound(musicVolume * masterVolume, 0.0, 1.0);

		FlxTween.tween(fromSound, {volume: FADE_MIN_VOLUME}, duration, {ease: FlxEase.quartIn});
		FlxTween.tween(toSound,   {volume: targetVolume},    duration, {
			ease: FlxEase.quartOut,
			onComplete: function(_:FlxTween):Void
			{
				fromSound.stop();
				_crossfadeActive = false;
			}
		});
	}

	public static function setPitch(value:Float):Void
	{
		_pitch = FlxMath.bound(value, 0.1, 4.0);
		_applyPitchToMusic();
		for (track in _tracks)
			if (track.sound != null && track.sound.alive)
				_applyPitchToSound(track.sound);
	}

	public static function getPitch():Float
	{
		return _pitch;
	}

	public static function setGlobalPan(value:Float):Void
	{
		_globalPan = FlxMath.bound(value, -1.0, 1.0);
		_applyPanToSound(FlxG.sound.music, _globalPan);
		for (track in _tracks)
			if (track.sound != null && track.sound.alive)
				_applyPanToSound(track.sound, _globalPan);
	}

	public static function setMusicLowPass(enabled:Bool, ?intensity:Float = 0.5):Void
	{
		_lowPassEnabled   = enabled;
		_lowPassIntensity = FlxMath.bound(intensity, 0.0, 1.0);

		var effect:AudioEffect = _getOrCreateEffect('lowpass');
		effect.enabled   = enabled;
		effect.intensity = _lowPassIntensity;

		_applyLowPassToMusic();
	}

	public static function setBassBoost(value:Float):Void
	{
		_bassBoost = FlxMath.bound(value, 0.0, 1.0);
		var effect:AudioEffect = _getOrCreateEffect('bass_boost');
		effect.enabled   = _bassBoost > 0;
		effect.intensity = _bassBoost;

		if (FlxG.sound.music != null)
		{
			var boosted:Float = FlxMath.bound(
				FlxG.sound.music.volume + _bassBoost * BASS_BOOST_MAX,
				0.0, 1.0
			);
			FlxG.sound.music.volume = boosted;
		}
	}

	public static function setCompressor(enabled:Bool):Void
	{
		_compressorEnabled     = enabled;
		var effect:AudioEffect = _getOrCreateEffect('compressor');
		effect.enabled         = enabled;
	}

	public static function duck(sounds:Array<FlxSound>, ?duration:Float = 0.0):Void
	{
		_duckedTracks = [];
		for (s in sounds)
		{
			if (s == null || !s.alive) continue;
			_duckedTracks.push({ sound: s, key: '', category: 'sfx', baseVolume: s.volume });
		}

		_isDucking    = true;
		_duckTimer    = 0.0;
		_duckDuration = duration;
	}

	public static function unduck():Void
	{
		_isDucking    = false;
		_duckTimer    = 0.0;
		_duckDuration = 0.0;

		for (track in _duckedTracks)
			if (track.sound != null && track.sound.alive)
				FlxTween.tween(track.sound, {volume: track.baseVolume}, DUCK_RESTORE_TIME, {ease: FlxEase.quartOut});

		_duckedTracks = [];
	}

	public static function duckMusic(?duration:Float = 0.0):Void
	{
		if (FlxG.sound.music != null)
			duck([FlxG.sound.music], duration);
	}

	public static function takeSnapshot():AudioSnapshot
	{
		var snapshot:AudioSnapshot = {
			musicVolume:  musicVolume,
			sfxVolume:    sfxVolume,
			masterVolume: masterVolume,
			pitch:        _pitch,
			timestamp:    Date.now().getTime()
		};
		_snapshots.push(snapshot);
		return snapshot;
	}

	public static function restoreSnapshot(?snapshot:AudioSnapshot):Void
	{
		var s:AudioSnapshot = snapshot != null ? snapshot
			: (_snapshots.length > 0 ? _snapshots[_snapshots.length - 1] : null);

		if (s == null) return;

		masterVolume = s.masterVolume;
		musicVolume  = s.musicVolume;
		sfxVolume    = s.sfxVolume;
		setPitch(s.pitch);

		if (snapshot == null && _snapshots.length > 0)
			_snapshots.pop();
	}

	public static function muteAll():Void
	{
		takeSnapshot();
		masterVolume = 0.0;
	}

	public static function unmuteAll():Void
	{
		restoreSnapshot();
	}

	public static function muteCategory(category:String):Void
	{
		for (track in _tracks)
			if (track.category == category && track.sound != null && track.sound.alive)
				track.sound.volume = 0.0;
	}

	public static function unmuteCategory(category:String):Void
	{
		for (track in _tracks)
			if (track.category == category && track.sound != null && track.sound.alive)
				track.sound.volume = FlxMath.bound(track.baseVolume, 0.0, 1.0);
	}

	public static function stopAll():Void
	{
		if (FlxG.sound.music != null) FlxG.sound.music.stop();
		for (track in _tracks)
			if (track.sound != null && track.sound.alive)
				track.sound.stop();
		_tracks = [];
	}

	public static function stopCategory(category:String):Void
	{
		for (track in _tracks)
			if (track.category == category && track.sound != null && track.sound.alive)
				track.sound.stop();
		_tracks = _tracks.filter((t:AudioTrack) -> t.category != category);
	}

	public static function pauseAll():Void
	{
		if (FlxG.sound.music != null) FlxG.sound.music.pause();
		for (track in _tracks)
			if (track.sound != null && track.sound.alive && track.sound.playing)
				track.sound.pause();
	}

	public static function resumeAll():Void
	{
		if (FlxG.sound.music != null) FlxG.sound.music.resume();
		for (track in _tracks)
			if (track.sound != null && track.sound.alive && !track.sound.playing)
				track.sound.resume();
	}

	public static function getActiveEffects():Array<AudioEffect>
	{
		return [for (_ => effect in _effects) if (effect.enabled) effect];
	}

	public static function isEffectEnabled(name:String):Bool
	{
		return _effects.exists(name) && _effects.get(name).enabled;
	}

	public static function resetEffects():Void
	{
		for (_ => effect in _effects)
		{
			effect.enabled   = false;
			effect.intensity = 0.0;
		}

		_bassBoost         = 0.0;
		_compressorEnabled = false;
		_lowPassEnabled    = false;
		_lowPassIntensity  = 0.5;
		_globalPan         = 0.0;
		setPitch(1.0);

		if (FlxG.sound.music != null)
			FlxG.sound.music.volume = FlxMath.bound(musicVolume * masterVolume, 0.0, 1.0);
	}

	public static function onSongBeat(beat:Int):Void
	{
		_beatCount = beat;
		if (onBeat != null) onBeat(beat);
	}

	public static function getMusicPosition():Float
	{
		return FlxG.sound.music != null ? FlxG.sound.music.time : 0.0;
	}

	public static function getMusicLength():Float
	{
		return FlxG.sound.music != null ? FlxG.sound.music.length : 0.0;
	}

	public static function getMusicProgress():Float
	{
		var len:Float = getMusicLength();
		return len > 0 ? FlxMath.bound(getMusicPosition() / len, 0.0, 1.0) : 0.0;
	}

	public static function isMusicPlaying():Bool
	{
		return FlxG.sound.music != null && FlxG.sound.music.playing;
	}

	public static function getActiveSoundCount(?category:String):Int
	{
		if (category == null)
			return _tracks.filter((t:AudioTrack) -> t.sound != null && t.sound.alive && t.sound.playing).length;
		return _tracks.filter((t:AudioTrack) -> t.category == category && t.sound != null && t.sound.alive && t.sound.playing).length;
	}

	private static function _applyPitchToMusic():Void
	{
		#if FLX_PITCH
		if (FlxG.sound.music != null)
			FlxG.sound.music.pitch = _pitch;
		#end
	}

	private static function _applyPitchToSound(sound:FlxSound):Void
	{
		#if FLX_PITCH
		if (sound != null) sound.pitch = _pitch;
		#end
	}

	private static function _applyPanToSound(sound:FlxSound, pan:Float):Void
	{
		if (sound == null) return;
		sound.pan = FlxMath.bound(pan, -1.0, 1.0);
	}

	private static function _applyLowPassToMusic():Void
	{
		if (FlxG.sound.music == null) return;
		var target:Float = _lowPassEnabled
			? FlxMath.bound(musicVolume * masterVolume * (1.0 - _lowPassIntensity * 0.6), 0.0, 1.0)
			: FlxMath.bound(musicVolume * masterVolume, 0.0, 1.0);
		FlxG.sound.music.volume = target;
	}

	private static function _applyCompressor():Void
	{
		if (FlxG.sound.music == null) return;
		var vol:Float = FlxG.sound.music.volume;
		if (vol > COMPRESSOR_THRESHOLD)
		{
			var excess:Float     = vol - COMPRESSOR_THRESHOLD;
			var compressed:Float = COMPRESSOR_THRESHOLD + (excess * COMPRESSOR_RATIO);
			FlxG.sound.music.volume = FlxMath.bound(compressed, 0.0, 1.0);
		}
	}

	private static function _getOrCreateEffect(name:String):AudioEffect
	{
		if (!_effects.exists(name))
			_effects.set(name, { name: name, intensity: 0.0, enabled: false });
		return _effects.get(name);
	}

	private static function _cleanTracks():Void
	{
		_tracks = _tracks.filter((t:AudioTrack) -> t.sound != null && t.sound.alive);
	}

	private static function _registerDefaultEffects():Void
	{
		for (name in ['lowpass', 'bass_boost', 'compressor', 'reverb', 'pan'])
			_getOrCreateEffect(name);
	}

	private static function set_masterVolume(value:Float):Float
	{
		masterVolume      = FlxMath.bound(value, 0.0, 1.0);
		FlxG.sound.volume = masterVolume;
		if (onVolumeChanged != null) onVolumeChanged(masterVolume);
		return masterVolume;
	}

	private static function set_musicVolume(value:Float):Float
	{
		musicVolume = FlxMath.bound(value, 0.0, 1.0);
		if (FlxG.sound.music != null)
			FlxG.sound.music.volume = FlxMath.bound(musicVolume * masterVolume, 0.0, 1.0);
		return musicVolume;
	}

	private static function set_sfxVolume(value:Float):Float
	{
		sfxVolume = FlxMath.bound(value, 0.0, 1.0);
		for (track in _tracks)
			if (track.category == 'sfx' && track.sound != null && track.sound.alive)
				track.sound.volume = FlxMath.bound(sfxVolume * masterVolume, 0.0, 1.0);
		return sfxVolume;
	}

	private static function set_uiVolume(value:Float):Float
	{
		uiVolume = FlxMath.bound(value, 0.0, 1.0);
		for (track in _tracks)
			if (track.category == 'ui' && track.sound != null && track.sound.alive)
				track.sound.volume = FlxMath.bound(uiVolume * masterVolume, 0.0, 1.0);
		return uiVolume;
	}
}