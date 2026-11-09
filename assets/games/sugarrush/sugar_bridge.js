/**
 * sugar_bridge.js
 * In-game bridge and WebSocket interceptor for Sugar Rush.
 */

window.__useBridgeSocket = true;

window.__sugarGame = {
  userCoins: 100000,
  userId: '10001',
  userUuid: '',
  userName: 'Player',
  userAvatar: '',
  roomId: '1',
  winRate: 75,
  poolBalance: 5000000,
  maxMultiplier: 10,
  chips: [100, 500, 1000, 5000],

  initUser: function(id, name, avatar, coins, roomId, winRate, uuid) {
    if (id) {
      var n = parseInt(id, 10);
      this.userId = (!isNaN(n) && n > 0) ? String(n) : '10001';
    }
    if (name) this.userName = String(name);
    if (avatar) this.userAvatar = String(avatar);
    if (coins !== undefined && coins !== null) this.userCoins = Number(coins);
    if (roomId) this.roomId = String(roomId);
    if (winRate !== undefined && winRate !== null) this.winRate = Number(winRate);
    if (uuid) this.userUuid = String(uuid);
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
  if (qUid) {
    var n = parseInt(qUid, 10);
    window.__sugarGame.userId = (!isNaN(n) && n > 0) ? String(n) : '10001';
  }
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
  var qUuid = urlParams.get('uuid');
  if (qUuid) window.__sugarGame.userUuid = qUuid;
} catch(e) {}

// ============================================================
// Supabase Online Integration for Ahla-Live Sugar Rush
// ============================================================
var SUPABASE_URL = 'https://pxyqgeitjdsilgfftnyd.supabase.co';
var SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB4eXFnZWl0amRzaWxnZmZ0bnlkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA2NzU5OTIsImV4cCI6MjEwNjI1MTk5Mn0.mWskb4-YFQNPDpGbF23g0ysmVGGkcm68SsJpNp_Y_bk';

function supabaseRequest(path, options) {
  options = options || {};
  options.headers = options.headers || {};
  options.headers['apikey'] = SUPABASE_ANON_KEY;
  options.headers['Authorization'] = 'Bearer ' + SUPABASE_ANON_KEY;
  options.headers['Content-Type'] = 'application/json';
  if (options.body && typeof options.body === 'object') {
    options.body = JSON.stringify(options.body);
  }
  return fetch(SUPABASE_URL + path, options).then(function(res) {
    if (!res.ok) throw new Error('HTTP ' + res.status);
    var ct = res.headers.get('content-type');
    if (ct && ct.includes('application/json')) return res.json();
    return res.text();
  });
}

function syncPoolConfig() {
  supabaseRequest('/rest/v1/game_jackpot_pool?id=eq.sugarrush&select=*')
    .then(function(data) {
      if (Array.isArray(data) && data.length > 0) {
        var cfg = data[0];
        if (cfg.win_rate != null) window.__sugarGame.winRate = Number(cfg.win_rate);
        if (cfg.pool_balance != null) window.__sugarGame.poolBalance = Number(cfg.pool_balance);
        if (cfg.max_multiplier != null) window.__sugarGame.maxMultiplier = Number(cfg.max_multiplier);
        console.log('[SugarGame] Synced pool config from Supabase: WinRate=' + window.__sugarGame.winRate + '% Pool=' + window.__sugarGame.poolBalance);
      }
    })
    .catch(function(err) {
      console.warn('[SugarGame] Could not sync pool config:', err);
    });
}

function syncUserData(uid) {
  if (!uid) return;
  var query = '/rest/v1/users?or=(uid.eq.' + encodeURIComponent(uid) + ',custom_id.eq.' + encodeURIComponent(uid) + ')&select=uid,name,coins,photo_url';
  supabaseRequest(query)
    .then(function(data) {
      if (Array.isArray(data) && data.length > 0) {
        var u = data[0];
        if (u.uid) window.__sugarGame.userId = String(u.uid);
        if (u.name) window.__sugarGame.userName = String(u.name);
        if (u.photo_url) window.__sugarGame.userAvatar = String(u.photo_url);
        if (u.coins != null) {
          window.__sugarGame.userCoins = Number(u.coins);
          console.log('[SugarGame] Synced user from Supabase:', u.name, 'Coins:', u.coins);
        }
      }
    })
    .catch(function(err) {
      console.warn('[SugarGame] Could not sync user data:', err);
    });
}

// ── Game records & ranking backed by Supabase game_bet_records ──
function fetchMyBetRecords(limit, cb) {
  var uid = window.__sugarGame.userUuid || '';
  if (!uid) { cb([]); return; }
  var path = '/rest/v1/game_bet_records?game_id=eq.sugarrush&user_id=eq.' +
    encodeURIComponent(uid) +
    '&order=created_at.desc&limit=' + (limit || 20) +
    '&select=bet_amount,win_amount,created_at';
  supabaseRequest(path)
    .then(function(rows) { cb(Array.isArray(rows) ? rows : []); })
    .catch(function(err) {
      console.warn('[SugarGame] fetchMyBetRecords error:', err);
      cb([]);
    });
}

function fetchTopPlayers(cb) {
  // Recent bets across all users → aggregate total win per user → top 10
  supabaseRequest('/rest/v1/game_bet_records?game_id=eq.sugarrush&select=user_id,user_name,win_amount&order=created_at.desc&limit=2000')
    .then(function(rows) {
      if (!Array.isArray(rows) || rows.length === 0) { cb([]); return; }
      var agg = {};
      var order = [];
      rows.forEach(function(r) {
        var uid = r.user_id || '';
        if (!uid) return;
        if (!agg[uid]) {
          agg[uid] = { uid: uid, name: r.user_name || 'Player', win: 0 };
          order.push(uid);
        }
        agg[uid].win += Number(r.win_amount) || 0;
      });
      var sorted = order.map(function(u) { return agg[u]; })
        .sort(function(a, b) { return b.win - a.win; })
        .slice(0, 10);

      // Resolve avatars from users table
      var uids = sorted.map(function(p) { return p.uid; });
      if (uids.length === 0) { cb(sorted); return; }
      var inFilter = uids.map(encodeURIComponent).join(',');
      supabaseRequest('/rest/v1/users?uid=in.(' + inFilter + ')&select=uid,photo_url')
        .then(function(users) {
          var photoMap = {};
          if (Array.isArray(users)) {
            users.forEach(function(u) { photoMap[u.uid] = u.photo_url || ''; });
          }
          sorted.forEach(function(p) { p.photo = photoMap[p.uid] || ''; });
          cb(sorted);
        })
        .catch(function() { cb(sorted); });
    })
    .catch(function(err) {
      console.warn('[SugarGame] fetchTopPlayers error:', err);
      cb([]);
    });
}

// Initial sync
try {
  syncPoolConfig();
  if (window.__sugarGame.userId) {
    syncUserData(window.__sugarGame.userId);
  }
} catch(e) {}


// Implement androidJsObj for NativeManager
window.androidJsObj = {
  getUid: function() {
    var pid = parseInt(window.__sugarGame.userId, 10);
    return String((!isNaN(pid) && pid > 0) ? pid : 10001);
  },
  getTicket: function() {
    var pid = parseInt(window.__sugarGame.userId, 10);
    return 'ticket_' + String((!isNaN(pid) && pid > 0) ? pid : 10001);
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
  getAppVersion: function() {
    return '1.0.0';
  },
  getAppOs: function() {
    return 'android';
  },
  getGameConfig: function() {
    var pid = parseInt(window.__sugarGame.userId, 10);
    if (isNaN(pid) || pid <= 0) pid = 10001;
    return JSON.stringify({
      gameType: 1,
      isProd: false,
      appDomain: '127.0.0.1',
      containerUrl: '127.0.0.1',
      serverAddress: '127.0.0.1',
      goldUrl: '',
      roomId: String(window.__sugarGame.roomId || '1'),
      platform: 'android',
      os: 'android',
      ticket: 'ticket_' + pid,
      playerId: pid,
      uid: String(pid)
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
      var pid = parseInt(window.__sugarGame.userId, 10);
      if (isNaN(pid) || pid <= 0) pid = 10001;

      if (handlerName === 'getUid') {
        resolve(String(pid));
      } else if (handlerName === 'getTicket') {
        resolve('ticket_' + pid);
      } else if (handlerName === 'getRoomId') {
        resolve(String(window.__sugarGame.roomId || '1'));
      } else if (handlerName === 'getLanguage') {
        resolve('en');
      } else if (handlerName === 'getAppDomain') {
        resolve('127.0.0.1');
      } else if (handlerName === 'getAppVersion') {
        resolve('1.0.0');
      } else if (handlerName === 'getAppOs') {
        resolve('android');
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

  // 1.5. MATCH REQ (.hall.MatchReq)
  if (header.includes('MATCH') || header.includes('Match') || header.includes('match') || header === '.hall.MatchReq') {
    setTimeout(function() {
      if (root.hall && root.hall.MatchRes) {
        var res = new root.hall.MatchRes({
          code: 0,
          desc: 'success',
          tableId: 'table_1'
        });
        var body = root.hall.MatchRes.encode(res).finish();
        self._sendPacket('.hall.MatchRes', body);
      }
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

  // 5. GETRECORD — real per-user bet history from game_bet_records
  if (header.includes('RECORD') || header.includes('getRecord')) {
    fetchMyBetRecords(20, function(rows) {
      try {
        var records = rows.map(function(r) {
          var win = Number(r.win_amount) || 0;
          var ts = 0;
          if (r.created_at) {
            var d = new Date(r.created_at);
            if (!isNaN(d.getTime())) ts = Math.floor(d.getTime() / 1000);
          }
          return new root.game.recordStruct({
            time: ts,
            betMoney: Number(r.bet_amount) || 0,
            symbolWinList: win > 0
              ? [new root.game.betStruct({ icon: 1, money: win })]
              : []
          });
        });
        var res = new root.game.s_c_getRecord({
          code: 0,
          desc: 'success',
          recordData: records
        });
        var body = root.game.s_c_getRecord.encode(res).finish();
        self._sendPacket('.game.s_c_getRecord', body);
      } catch(e) {
        console.error('[BridgeWebSocket] getRecord encode error:', e);
      }
    });
    return;
  }

  // 6. GETRANKDATA — real top winners leaderboard
  if (header.includes('RANK') || header.includes('getRankData')) {
    fetchTopPlayers(function(players) {
      try {
        var rankData = players.map(function(p) {
          return new root.game.rankStruct({
            name: p.name || 'Player',
            head: p.photo || '',
            winMoney: Number(p.win) || 0
          });
        });
        var res = new root.game.s_c_getRankData({
          code: 0,
          desc: 'success',
          rankData: rankData,
          tipType: 0
        });
        var body = root.game.s_c_getRankData.encode(res).finish();
        self._sendPacket('.game.s_c_getRankData', body);
      } catch(e) {
        console.error('[BridgeWebSocket] getRankData encode error:', e);
      }
    });
    return;
  }

  // 7. BET / SPIN
  if (header.includes('BET') || header.includes('bet') || header.includes('DOSLOTS')) {
    var req = root.game.c_s_bet.decode(protoBytes);
    var betAmount = req.betMoney || 100;
    console.log('[BridgeWebSocket] User Bet Amount:', betAmount);

    // Insufficient balance → block the spin and open the recharge page
    if ((window.__sugarGame.userCoins || 0) < betAmount) {
      console.log('[BridgeWebSocket] Insufficient coins:', window.__sugarGame.userCoins, '<', betAmount);
      if (window.androidJsObj && window.androidJsObj.openChargePage) {
        try { window.androidJsObj.openChargePage(); } catch(e) {}
      }
      if (window.FlutterBridge && window.FlutterBridge.postMessage) {
        window.FlutterBridge.postMessage(JSON.stringify({ action: 'charge' }));
      }
      setTimeout(function() {
        var res = new root.game.s_c_bet({
          code: 1,
          desc: 'insufficient coins',
          tipType: 0,
          money: Number(window.__sugarGame.userCoins) || 0,
          symbols: []
        });
        var body = root.game.s_c_bet.encode(res).finish();
        self._sendPacket('.game.s_c_bet', body);
      }, 50);
      return;
    }

    if (window.FlutterBridge && window.FlutterBridge.postMessage) {
      window.FlutterBridge.postMessage(JSON.stringify({
        action: 'bet',
        betMoney: betAmount,
        roomId: window.__sugarGame.roomId,
        userId: window.__sugarGame.userId
      }));
    } else {
      // Direct Web Mode: Sync bet deduction to Supabase
      try {
        var uid = window.__sugarGame.userId;
        var postBetCoins = Math.max(0, window.__sugarGame.userCoins - betAmount);
        supabaseRequest('/rest/v1/users?or=(uid.eq.' + encodeURIComponent(uid) + ',custom_id.eq.' + encodeURIComponent(uid) + ')', {
          method: 'PATCH',
          body: { coins: postBetCoins }
        }).catch(function(e){ console.warn('[SugarGame] Supabase bet coins sync error:', e); });
      } catch(e) {}
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
    } else {
      // Direct Web Mode: Sync win coins and log bet record to Supabase
      try {
        var uid = window.__sugarGame.userId;
        var finalCoins = window.__sugarGame.userCoins;
        if (winAmount > 0) {
          supabaseRequest('/rest/v1/users?or=(uid.eq.' + encodeURIComponent(uid) + ',custom_id.eq.' + encodeURIComponent(uid) + ')', {
            method: 'PATCH',
            body: { coins: finalCoins }
          }).catch(function(e){ console.warn('[SugarGame] Supabase win coins sync error:', e); });
        }
        // Insert game bet record
        supabaseRequest('/rest/v1/game_bet_records', {
          method: 'POST',
          body: {
            game_id: 'sugarrush',
            user_id: uid,
            room_id: window.__sugarGame.roomId || '1',
            user_name: window.__sugarGame.userName || 'Player',
            bet_amount: betAmount,
            win_amount: winAmount,
            net_result: winAmount - betAmount,
            is_win: isWin,
            created_at: new Date().toISOString()
          }
        }).catch(function(e){ console.warn('[SugarGame] Supabase bet record insert error:', e); });

        // Update pool balance in game_jackpot_pool
        var netChange = betAmount - winAmount;
        if (netChange !== 0) {
          window.__sugarGame.poolBalance += netChange;
          supabaseRequest('/rest/v1/game_jackpot_pool?id=eq.sugarrush', {
            method: 'PATCH',
            body: {
              pool_balance: window.__sugarGame.poolBalance,
              updated_at: new Date().toISOString()
            }
          }).catch(function(e){ console.warn('[SugarGame] Supabase pool balance update error:', e); });
        }
      } catch(e) {}
    }

    // Ensure symbolInfo decode safety net for out-of-bound item access
    if (root.game && root.game.symbolInfo && !root.game.symbolInfo.__safePatched) {
      root.game.symbolInfo.__safePatched = true;
      var origDecode = root.game.symbolInfo.decode;
      root.game.symbolInfo.decode = function(r, l) {
        var obj = origDecode.call(this, r, l);
        if (obj && obj.matrixProtoList && typeof Proxy !== 'undefined') {
          var rawList = obj.matrixProtoList;
          obj.matrixProtoList = new Proxy(rawList, {
            get: function(target, prop) {
              if (typeof prop === 'string' && !isNaN(prop)) {
                var n = parseInt(prop, 10);
                if (n >= 0 && (!target[n] || target[n].number === undefined)) {
                  return { row: 0, column: 0, number: Math.floor(Math.random() * 7) + 1 };
                }
              }
              return target[prop];
            }
          });
        }
        return obj;
      };
    }

    // Grid in SugarRush is 6 columns by 6 rows (36 items total)
    var matrix = [];
    for (var c = 0; c < 6; c++) {
      for (var r = 0; r < 6; r++) {
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
      for (var w = 0; w < 6; w++) {
        matrix[w].number = winNum;
      }
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
