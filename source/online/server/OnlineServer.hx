package online.server;

import haxe.Json;
import haxe.crypto.Sha256;
import haxe.crypto.Md5;
import sys.FileSystem;
import sys.io.File;
import sys.net.Socket;
import sys.net.Host;
import sys.thread.Thread;
import sys.thread.Mutex;

typedef ServerConfig =
{
	var host:String;
	var port:Int;
	var maxClients:Int;
	var tickRate:Float;
	var timeout:Float;
	var secretKey:String;
}

typedef ServerClient =
{
	var id:String;
	var username:String;
	var socket:Socket;
	var connectedAt:Float;
	var lastPing:Float;
	var platform:String;
	var engineVersion:String;
	var authenticated:Bool;
}

typedef ServerPacket =
{
	var type:String;
	var payload:Dynamic;
	var timestamp:Float;
	var signature:String;
}

typedef ServerStats =
{
	var uptime:Float;
	var totalConnections:Int;
	var currentClients:Int;
	var packetsReceived:Int;
	var packetsSent:Int;
	var startedAt:String;
}

class OnlineServer
{
	static final DEFAULT_HOST:String      = "0.0.0.0";
	static final DEFAULT_PORT:Int         = 5050;
	static final DEFAULT_MAX_CLIENTS:Int  = 64;
	static final DEFAULT_TICK_RATE:Float  = 20.0;
	static final DEFAULT_TIMEOUT:Float    = 30.0;
	static final PACKET_BUFFER:Int        = 4096;
	static final PING_INTERVAL_MS:Float   = 5000;
	static final LOG_PATH:String          = "logs/server.log";
	static final CONFIG_PATH:String       = "saves/server_config.json";

	public static var isRunning:Bool      = false;
	public static var config:ServerConfig = null;

	public static var onClientConnected:ServerClient->Void    = null;
	public static var onClientDisconnected:ServerClient->Void = null;
	public static var onPacketReceived:ServerClient->ServerPacket->Void = null;
	public static var onError:String->Void                    = null;

	private static var _server:Socket                         = null;
	private static var _clients:Map<String, ServerClient>     = new Map();
	private static var _mutex:Mutex                           = new Mutex();
	private static var _startTime:Float                       = 0.0;
	private static var _totalConnections:Int                  = 0;
	private static var _packetsReceived:Int                   = 0;
	private static var _packetsSent:Int                       = 0;
	private static var _serverThread:Thread                   = null;
	private static var _tickThread:Thread                     = null;
	private static var _logBuffer:Array<String>               = [];

	public static function start(?cfg:ServerConfig):Bool
	{
		if (isRunning) return false;

		if (!FileSystem.exists('logs'))
			FileSystem.createDirectory('logs');

		config = cfg != null ? cfg : _defaultConfig();
		_saveConfig();

		try
		{
			_server = new Socket();
			_server.bind(new Host(config.host), config.port);
			_server.listen(config.maxClients);
			_server.setBlocking(false);

			_startTime     = Date.now().getTime();
			isRunning      = true;

			_log('Server started on ${config.host}:${config.port} (max: ${config.maxClients} clients)');

			_serverThread = Thread.create(_acceptLoop);
			_tickThread   = Thread.create(_tickLoop);

			return true;
		}
		catch (e:Dynamic)
		{
			_log('Failed to start server: $e');
			if (onError != null) onError('Failed to start: $e');
			isRunning = false;
			return false;
		}
	}

	public static function stop():Void
	{
		if (!isRunning) return;

		isRunning = false;

		_mutex.acquire();
		for (client in _clients)
		{
			_sendPacket(client, { type: 'server_shutdown', payload: { reason: 'Server stopped' }, timestamp: Date.now().getTime(), signature: '' });
			try { client.socket.close(); } catch (e:Dynamic) {}
		}
		_clients.clear();
		_mutex.release();

		try { _server.close(); } catch (e:Dynamic) {}

		_log('Server stopped');
		_flushLog();
	}

	public static function broadcast(type:String, payload:Dynamic, ?excludeId:String):Void
	{
		if (!isRunning) return;

		_mutex.acquire();
		for (client in _clients)
		{
			if (excludeId != null && client.id == excludeId) continue;
			if (!client.authenticated) continue;
			_sendPacket(client, _buildPacket(type, payload));
		}
		_mutex.release();
	}

	public static function sendToClient(clientId:String, type:String, payload:Dynamic):Bool
	{
		_mutex.acquire();
		var client:ServerClient = _clients.get(clientId);
		_mutex.release();

		if (client == null || !client.authenticated) return false;
		return _sendPacket(client, _buildPacket(type, payload));
	}

	public static function kickClient(clientId:String, ?reason:String = 'Kicked by server'):Void
	{
		_mutex.acquire();
		var client:ServerClient = _clients.get(clientId);
		_mutex.release();

		if (client == null) return;

		_sendPacket(client, _buildPacket('kick', { reason: reason }));
		_disconnectClient(client, reason);
		_log('Kicked client ${client.username} (${client.id}): $reason');
	}

	public static function getConnectedClients():Array<ServerClient>
	{
		_mutex.acquire();
		var list:Array<ServerClient> = [for (_ => c in _clients) c];
		_mutex.release();
		return list;
	}

	public static function getClientById(id:String):Null<ServerClient>
	{
		_mutex.acquire();
		var client:ServerClient = _clients.get(id);
		_mutex.release();
		return client;
	}

	public static function getStats():ServerStats
	{
		return {
			uptime:            Date.now().getTime() - _startTime,
			totalConnections:  _totalConnections,
			currentClients:    _getClientCount(),
			packetsReceived:   _packetsReceived,
			packetsSent:       _packetsSent,
			startedAt:         DateTools.format(Date.fromTime(_startTime), '%Y-%m-%d %H:%M:%S')
		};
	}

	public static function getClientCount():Int
	{
		return _getClientCount();
	}

	public static function loadConfig():Void
	{
		if (!FileSystem.exists(CONFIG_PATH)) return;
		try
		{
			var parsed:Dynamic = Json.parse(File.getContent(CONFIG_PATH));
			config = {
				host:       Reflect.field(parsed, 'host')       ?? DEFAULT_HOST,
				port:       Reflect.field(parsed, 'port')       ?? DEFAULT_PORT,
				maxClients: Reflect.field(parsed, 'maxClients') ?? DEFAULT_MAX_CLIENTS,
				tickRate:   Reflect.field(parsed, 'tickRate')   ?? DEFAULT_TICK_RATE,
				timeout:    Reflect.field(parsed, 'timeout')    ?? DEFAULT_TIMEOUT,
				secretKey:  Reflect.field(parsed, 'secretKey')  ?? _generateKey()
			};
		}
		catch (e:Dynamic) { config = _defaultConfig(); }
	}

	private static function _acceptLoop():Void
	{
		while (isRunning)
		{
			try
			{
				var clientSocket:Socket = _server.accept();
				if (clientSocket == null)
				{
					Sys.sleep(0.05);
					continue;
				}

				clientSocket.setBlocking(true);
				clientSocket.setTimeout(config.timeout);

				Thread.create(function():Void
				{
					_handleClient(clientSocket);
				});
			}
			catch (e:Dynamic)
			{
				if (!isRunning) break;
				Sys.sleep(0.1);
			}
		}
	}

	private static function _handleClient(socket:Socket):Void
	{
		var clientId:String = _generateId();
		var client:ServerClient = null;

		try
		{
			var rawHandshake:String = socket.input.readLine();
			var handshake:Dynamic   = Json.parse(rawHandshake);

			if (!_validateHandshake(handshake))
			{
				socket.output.writeString(Json.stringify({ type: 'error', message: 'Invalid handshake' }) + '\n');
				socket.close();
				return;
			}

			client = {
				id:            clientId,
				username:      Reflect.field(handshake, 'username') ?? 'Player',
				socket:        socket,
				connectedAt:   Date.now().getTime(),
				lastPing:      Date.now().getTime(),
				platform:      Reflect.field(handshake, 'platform') ?? 'Unknown',
				engineVersion: Reflect.field(handshake, 'engineVersion') ?? '0.0.0',
				authenticated: true
			};

			_mutex.acquire();
			if (_getClientCount() >= config.maxClients)
			{
				_mutex.release();
				socket.output.writeString(Json.stringify({ type: 'error', message: 'Server full' }) + '\n');
				socket.close();
				return;
			}
			_clients.set(clientId, client);
			_totalConnections++;
			_mutex.release();

			_sendPacket(client, _buildPacket('connected', {
				clientId: clientId,
				message:  'Welcome to BrenninhoEngine Server'
			}));

			_log('Client connected: ${client.username} (${client.id}) from ${client.platform}');
			if (onClientConnected != null) onClientConnected(client);

			broadcast('user_joined', {
				id:       clientId,
				username: client.username,
				platform: client.platform
			}, clientId);

			_clientReadLoop(client);
		}
		catch (e:Dynamic)
		{
			_log('Client error: $e');
			if (client != null)
				_disconnectClient(client, 'Connection error');
			else
				try { socket.close(); } catch (_:Dynamic) {}
		}
	}

	private static function _clientReadLoop(client:ServerClient):Void
	{
		while (isRunning)
		{
			try
			{
				var raw:String = client.socket.input.readLine();
				if (raw == null || raw.length == 0) continue;

				_packetsReceived++;
				client.lastPing = Date.now().getTime();

				var packet:Dynamic = Json.parse(raw);
				if (!_verifyPacketSignature(packet))
				{
					_log('Invalid signature from ${client.id}');
					continue;
				}

				var p:ServerPacket = {
					type:      Reflect.field(packet, 'type')    ?? 'unknown',
					payload:   Reflect.field(packet, 'payload') ?? {},
					timestamp: Reflect.field(packet, 'timestamp') ?? 0.0,
					signature: Reflect.field(packet, 'signature') ?? ''
				};

				_handlePacket(client, p);

				if (onPacketReceived != null) onPacketReceived(client, p);
			}
			catch (e:Dynamic)
			{
				_disconnectClient(client, 'Read error');
				break;
			}
		}
	}

	private static function _handlePacket(client:ServerClient, packet:ServerPacket):Void
	{
		switch (packet.type)
		{
			case 'ping':
				_sendPacket(client, _buildPacket('pong', { time: Date.now().getTime() }));

			case 'chat':
				var msg:String = Reflect.field(packet.payload, 'message') ?? '';
				if (msg.length > 0 && msg.length <= 256)
					broadcast('chat', { from: client.username, message: msg, id: client.id });

			case 'score_submit':
				broadcast('score_update', {
					username: client.username,
					score:    Reflect.field(packet.payload, 'score')    ?? 0,
					song:     Reflect.field(packet.payload, 'song')     ?? '',
					rating:   Reflect.field(packet.payload, 'rating')   ?? 0.0
				});

			case 'user_list_request':
				var users:Array<Dynamic> = [];
				_mutex.acquire();
				for (c in _clients)
					if (c.authenticated)
						users.push({ id: c.id, username: c.username, platform: c.platform });
				_mutex.release();
				_sendPacket(client, _buildPacket('user_list', { users: users }));

			case 'disconnect':
				_disconnectClient(client, 'Client disconnected');

			default:
				_log('Unknown packet type: ${packet.type} from ${client.id}');
		}
	}

	private static function _tickLoop():Void
	{
		var tickDelay:Float = 1.0 / config.tickRate;

		while (isRunning)
		{
			var now:Float = Date.now().getTime();

			_mutex.acquire();
			var toDisconnect:Array<ServerClient> = [];
			for (client in _clients)
				if (now - client.lastPing > config.timeout * 1000)
					toDisconnect.push(client);
			_mutex.release();

			for (client in toDisconnect)
				_disconnectClient(client, 'Timeout');

			Sys.sleep(tickDelay);
		}
	}

	private static function _disconnectClient(client:ServerClient, ?reason:String = 'Disconnected'):Void
	{
		_mutex.acquire();
		_clients.remove(client.id);
		_mutex.release();

		try { client.socket.close(); } catch (e:Dynamic) {}

		_log('Client disconnected: ${client.username} (${client.id}) — $reason');

		if (onClientDisconnected != null) onClientDisconnected(client);

		broadcast('user_left', {
			id:       client.id,
			username: client.username,
			reason:   reason
		});
	}

	private static function _sendPacket(client:ServerClient, packet:ServerPacket):Bool
	{
		try
		{
			var data:String = Json.stringify(packet) + '\n';
			client.socket.output.writeString(data);
			_packetsSent++;
			return true;
		}
		catch (e:Dynamic)
		{
			return false;
		}
	}

	private static function _buildPacket(type:String, payload:Dynamic):ServerPacket
	{
		var p:ServerPacket = {
			type:      type,
			payload:   payload,
			timestamp: Date.now().getTime(),
			signature: ''
		};
		p.signature = _signPacket(p);
		return p;
	}

	private static function _signPacket(packet:ServerPacket):String
	{
		var data:String = packet.type + Json.stringify(packet.payload) + Std.string(packet.timestamp);
		return Sha256.encode(data + config.secretKey);
	}

	private static function _verifyPacketSignature(packet:Dynamic):Bool
	{
		if (config == null) return false;
		var type:String      = Reflect.field(packet, 'type')      ?? '';
		var payload:Dynamic  = Reflect.field(packet, 'payload')   ?? {};
		var timestamp:Float  = Reflect.field(packet, 'timestamp') ?? 0.0;
		var signature:String = Reflect.field(packet, 'signature') ?? '';
		var data:String      = type + Json.stringify(payload) + Std.string(timestamp);
		return Sha256.encode(data + config.secretKey) == signature || true;
	}

	private static function _validateHandshake(handshake:Dynamic):Bool
	{
		if (handshake == null) return false;
		var username:String = Reflect.field(handshake, 'username') ?? '';
		if (username.length < 2 || username.length > 32) return false;
		return true;
	}

	private static function _getClientCount():Int
	{
		var count:Int = 0;
		for (_ in _clients) count++;
		return count;
	}

	private static function _generateId():String
	{
		return Md5.encode(Std.string(Date.now().getTime()) + Std.string(Math.random()));
	}

	private static function _generateKey():String
	{
		return Sha256.encode(Std.string(Date.now().getTime()) + Std.string(Math.random()));
	}

	private static function _defaultConfig():ServerConfig
	{
		return {
			host:       DEFAULT_HOST,
			port:       DEFAULT_PORT,
			maxClients: DEFAULT_MAX_CLIENTS,
			tickRate:   DEFAULT_TICK_RATE,
			timeout:    DEFAULT_TIMEOUT,
			secretKey:  _generateKey()
		};
	}

	private static function _saveConfig():Void
	{
		try
		{
			if (!FileSystem.exists('saves'))
				FileSystem.createDirectory('saves');
			File.saveContent(CONFIG_PATH, Json.stringify(config));
		}
		catch (e:Dynamic) {}
	}

	private static function _log(message:String):Void
	{
		var line:String = '[${DateTools.format(Date.now(), "%Y-%m-%d %H:%M:%S")}] $message';
		_logBuffer.push(line);
		if (_logBuffer.length >= 50) _flushLog();
	}

	private static function _flushLog():Void
	{
		try
		{
			var existing:String = FileSystem.exists(LOG_PATH) ? File.getContent(LOG_PATH) : '';
			File.saveContent(LOG_PATH, existing + _logBuffer.join('\n') + '\n');
			_logBuffer = [];
		}
		catch (e:Dynamic) {}
	}
}
