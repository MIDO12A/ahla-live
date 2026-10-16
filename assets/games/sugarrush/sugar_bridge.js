/**
 * sugar_bridge.js
 * In-game bridge and WebSocket interceptor for Sugar Rush.
 */

window.__useBridgeSocket = true;

window.__sugarGame = {
  userCoins: 100000,
  userId: '10001',
  userName: 'Player',
  userAvatar: '',
  roomId: '1',
  winRate: 75,
  poolBalance: 5000000,
  maxMultiplier: 10,
  chips: [100, 500, 1000, 5000],
  
  initUser: function(id, name, avatar, coins, roomId, winRate) {
    if (id) this.userId = String(id);
    if (name) this.userName = String(name);
    if (avatar) this.userAvatar = String(avatar);
    if (coins !== undefined && coins !== null) this.userCoins = Number(coins);
    if (roomId) this.roomId = String(roomId);
    if (winRate !== undefined && winRate !== null) this.winRate = Number(winRate);
    console.log('[SugarGame] Initialized user:', this.userId, this.userName, 'Coins:', this.userCoins);
  },

  updateCoins: function(newCoins) {
    this.userCoins = Number(newCoins);
    console.log('[SugarGame] Updated coins:', this.userCoins);
  }
};

// Immediately parse any URL query params so they are available synchronously
try {
  var urlParams = new URLSearchParams(window.location.search);
  var qUid = urlParams.get('uid') || urlParams.get('playerId');
  if (qUid) window.__sugarGame.userId = qUid;
  var qRoom = urlParams.get('roomId');
  if (qRoom) window.__sugarGame.roomId = qRoom;
  var qCoins = urlParams.get('coins');
  if (qCoins) window.__sugarGame.userCoins = Number(qCoins);
  var qWin = urlParams.get('winRate');
  if (qWin) window.__sugarGame.winRate = Number(qWin);
  var qName = urlParams.get('name');
  if (qName) window.__sugarGame.userName = qName;
  var qAvatar = urlParams.get('avatar');
  if (qAvatar) window.__sugarGame.userAvatar = qAvatar;
} catch(e) {}

// Implement androidJsObj for NativeManager
window.androidJsObj = {
  getUid: function() {
    return String(window.__sugarGame.userId || '10001');
  },
  getTicket: function() {
    return 'ticket_' + String(window.__sugarGame.userId || '10001');
  },
  getRoomId: function() {
    return String(window.__sugarGame.roomId || '1');
  },
  getLanguage: function() {
    return 'en';
  },
  getAppDomain: function() {
    return '127.0.0.1';
  },
  getGameConfig: function() {
    return JSON.stringify({
      gameType: 1,
      isProd: false,
      appDomain: '127.0.0.1',
      roomId: String(window.__sugarGame.roomId || '1'),
      platform: 'android',
      os: 'android',
      ticket: 'ticket_' + String(window.__sugarGame.userId || '10001'),
      playerId: Number(window.__sugarGame.userId) || 10001,
      uid: String(window.__sugarGame.userId || '10001')
    });
  },
  closeWin: function() {
    if (window.FlutterBridge && window.FlutterBridge.postMessage) {
      window.FlutterBridge.postMessage(JSON.stringify({ action: 'close' }));
    }
  },
  closeLoadingView: function() {
    var splash = document.getElementById('splash');
    if (splash) splash.style.display = 'none';
    var log = document.getElementById('log-container');
    if (log) log.style.display = 'none';
  },
  openChargePage: function() {
    if (window.FlutterBridge && window.FlutterBridge.postMessage) {
      window.FlutterBridge.postMessage(JSON.stringify({ action: 'charge' }));
    }
  },
  trackBettingEvent: function(evt) {
    console.log('[androidJsObj] trackBettingEvent:', evt);
  }
};

// Implement flutter_inappwebview for NativeManager
window.flutter_inappwebview = {
  callHandler: function(handlerName, args) {
    return new Promise(function(resolve) {
      if (handlerName === 'getUid') {
        resolve(String(window.__sugarGame.userId || '10001'));
      } else if (handlerName === 'getTicket') {
        resolve('ticket_' + String(window.__sugarGame.userId || '10001'));
      } else if (handlerName === 'getRoomId') {
        resolve(String(window.__sugarGame.roomId || '1'));
      } else if (handlerName === 'getLanguage') {
        resolve('en');
      } else if (handlerName === 'getAppDomain') {
        resolve('127.0.0.1');
      } else if (handlerName === 'getGameConfig') {
        resolve(window.androidJsObj.getGameConfig());
      } else if (handlerName === 'closeWin') {
        window.androidJsObj.closeWin();
        resolve(true);
      } else if (handlerName === 'closeLoadingView') {
        window.androidJsObj.closeLoadingView();
        resolve(true);
      } else {
        resolve('');
      }
    });
  }
};

window.__BridgeWebSocket = function(url) {
  console.log('[BridgeWebSocket] Connected to virtual socket URL:', url);
  this.url = url;
  this.readyState = 0;
  this.onopen = null;
  this.onclose = null;
  this.onerror = null;
  this.onmessage = null;

  var self = this;
  setTimeout(function() {
    self.readyState = 1;
    if (typeof self.onopen === 'function') {
      self.onopen({ type: 'open' });
    }
  }, 100);
};

window.__BridgeWebSocket.prototype.close = function() {
  console.log('[BridgeWebSocket] Closed socket');
  this.readyState = 3;
  if (typeof this.onclose === 'function') {
    this.onclose({ code: 1000, reason: 'Normal Closure' });
  }
};

window.__BridgeWebSocket.prototype.send = function(data) {
  var self = this;
  if (!data) return;

  try {
    var raw = data;
    if (raw.buffer && raw.buffer instanceof ArrayBuffer) {
      raw = raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength);
    }
    
    var dv = new DataView(raw);
    var totalLen = dv.getUint16(0, false);
    var headerLen = dv.getUint16(2, false);
    var headerBytes = new Uint8Array(raw, 4, headerLen);
    var header = new TextDecoder().decode(headerBytes);
    var protoBytes = new Uint8Array(raw, 4 + headerLen);

    console.log('[BridgeWebSocket] Intercepted Packet Header:', header);
    self._handlePacket(header, protoBytes);
  } catch(e) {
    console.error('[BridgeWebSocket] Error parsing packet:', e);
  }
};

window.__BridgeWebSocket.prototype._handlePacket = function(header, protoBytes) {
  var self = this;
  var root = window.protobuf && window.protobuf.roots && window.protobuf.roots.creator;
  if (!root) {
    console.error('[BridgeWebSocket] Protobuf roots not initialized yet!');
    return;
  }

  // 1. LOGIN REQ
  if (header.includes('LOGIN') || header.includes('login') || header === '.login.LoginReq') {
    setTimeout(function() {
      var res = new root.login.LoginRes({
        code: 0,
        desc: 'success',
        playerId: Number(window.__sugarGame.userId) || 10001,
        tableId: 'table_1',
        name: window.__sugarGame.userName || 'Player',
        head: window.__sugarGame.userAvatar || '',
        userMoney: Number(window.__sugarGame.userCoins) || 100000,
        erbanNo: String(window.__sugarGame.userId || '10001'),
        tipType: 0
      });
      var body = root.login.LoginRes.encode(res).finish();
      self._sendPacket('.login.LoginRes', body);
    }, 50);
    return;
  }

  // 2. GETCONFIG / CHIP CONFIG
  if (header.includes('CONFIG') || header.includes('ChipCfg')) {
    setTimeout(function() {
      var res = new root.game.s_c_getChipCfgRes({
        code: 0,
        desc: 'success',
        addPer: 1,
        availableChips: window.__sugarGame.chips || [100, 500, 1000, 5000]
      });
      var body = root.game.s_c_getChipCfgRes.encode(res).finish();
      self._sendPacket('.game.s_c_getChipCfgRes', body);
    }, 50);
    return;
  }

  // 3. GETUSERDATA
  if (header.includes('USERDATA') || header.includes('getUserData')) {
    setTimeout(function() {
      var res = new root.game.s_c_getUserData({
        code: 0,
        desc: 'success',
        id: Number(window.__sugarGame.userId) || 10001,
        name: window.__sugarGame.userName || 'Player',
        head: window.__sugarGame.userAvatar || '',
        userMoney: Number(window.__sugarGame.userCoins) || 100000,
        erbanNo: Number(window.__sugarGame.userId) || 10001,
        tipType: 0
      });
      var body = root.game.s_c_getUserData.encode(res).finish();
      self._sendPacket('.game.s_c_getUserData', body);
    }, 50);
    return;
  }

  // 4. HEARTBEAT
  if (header.includes('HEART') || header.includes('HeartBeat')) {
    setTimeout(function() {
      var res = new root.game.HeartBeatRsp({
        time: Date.now()
      });
      var body = root.game.HeartBeatRsp.encode(res).finish();
      self._sendPacket('.game.HeartBeatRsp', body);
    }, 20);
    return;
  }

  // 5. GETRECORD
  if (header.includes('RECORD') || header.includes('getRecord')) {
    setTimeout(function() {
      var res = new root.game.s_c_getRecord({
        code: 0,
        desc: 'success',
        recordData: []
      });
      var body = root.game.s_c_getRecord.encode(res).finish();
      self._sendPacket('.game.s_c_getRecord', body);
    }, 50);
    return;
  }

  // 6. GETRANKDATA
  if (header.includes('RANK') || header.includes('getRankData')) {
    setTimeout(function() {
      var res = new root.game.s_c_getRankData({
        code: 0,
        desc: 'success',
        rankData: [],
        tipType: 0
      });
      var body = root.game.s_c_getRankData.encode(res).finish();
      self._sendPacket('.game.s_c_getRankData', body);
    }, 50);
    return;
  }

  // 7. BET / SPIN
  if (header.includes('BET') || header.includes('bet') || header.includes('DOSLOTS')) {
    var req = root.game.c_s_bet.decode(protoBytes);
    var betAmount = req.betMoney || 100;
    console.log('[BridgeWebSocket] User Bet Amount:', betAmount);

    if (window.FlutterBridge && window.FlutterBridge.postMessage) {
      window.FlutterBridge.postMessage(JSON.stringify({
        action: 'bet',
        betMoney: betAmount,
        roomId: window.__sugarGame.roomId,
        userId: window.__sugarGame.userId
      }));
    }

    window.__sugarGame.userCoins = Math.max(0, window.__sugarGame.userCoins - betAmount);

    var isWin = (Math.random() * 100) < window.__sugarGame.winRate;
    var multiplier = 0;
    var winAmount = 0;

    if (isWin) {
      var multipliers = [1.2, 1.5, 2.0, 3.0, 5.0];
      multiplier = multipliers[Math.floor(Math.random() * multipliers.length)];
      winAmount = Math.round(betAmount * multiplier);
      window.__sugarGame.userCoins += winAmount;
    }

    console.log('[BridgeWebSocket] Spin Result -> Win:', isWin, 'WinAmount:', winAmount, 'Remaining:', window.__sugarGame.userCoins);

    if (window.FlutterBridge && window.FlutterBridge.postMessage) {
      window.FlutterBridge.postMessage(JSON.stringify({
        action: 'spin_result',
        betMoney: betAmount,
        winMoney: winAmount,
        userCoins: window.__sugarGame.userCoins,
        isWin: isWin
      }));
    }

    var matrix = [];
    for (var r = 0; r < 5; r++) {
      for (var c = 0; c < 3; c++) {
        var num = Math.floor(Math.random() * 7) + 1;
        matrix.push(new root.game.posInfo({
          row: r,
          column: c,
          number: num
        }));
      }
    }

    if (isWin) {
      var winNum = Math.floor(Math.random() * 6) + 1;
      matrix[0].number = winNum;
      matrix[1].number = winNum;
      matrix[3].number = winNum;
      matrix[4].number = winNum;
    }

    setTimeout(function() {
      var res = new root.game.s_c_bet({
        code: 0,
        desc: 'success',
        tipType: 0,
        money: window.__sugarGame.userCoins,
        symbols: [
          new root.game.symbolInfo({
            winMoney: winAmount,
            freeTimes: 0,
            matrixProtoList: matrix,
            updatePosList: []
          })
        ]
      });

      var body = root.game.s_c_bet.encode(res).finish();
      self._sendPacket('.game.s_c_bet', body);
    }, 150);
    return;
  }

  console.warn('[BridgeWebSocket] Unhandled packet header:', header);
};

window.__BridgeWebSocket.prototype._sendPacket = function(header, protoBytes) {
  if (typeof this.onmessage !== 'function') return;

  var headerBytes = new TextEncoder().encode(header);
  var H = headerBytes.length;
  var B = protoBytes.length;
  var payloadLen = 2 + H + B;

  var packet = new Uint8Array(2 + payloadLen);
  var dv = new DataView(packet.buffer);
  dv.setUint16(0, payloadLen, false);
  dv.setUint16(2, H, false);
  packet.set(headerBytes, 4);
  packet.set(protoBytes, 4 + H);

  var blob = new Blob([packet], { type: 'application/octet-stream' });
  this.onmessage({ data: blob });
};

window.androidJsObj = window.androidJsObj || {};
window.androidJsObj.closeWin = function() {
  if (window.FlutterBridge && window.FlutterBridge.postMessage) {
    window.FlutterBridge.postMessage(JSON.stringify({ action: 'close' }));
  }
};
window.androidJsObj.getUid = function() {
  return window.__sugarGame.userId;
};
window.androidJsObj.getRoomId = function() {
  return window.__sugarGame.roomId;
};
