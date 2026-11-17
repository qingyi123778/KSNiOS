/* KSN iOS · 签到引擎
 * 只做签到链路：活动列表 → 签到码 → 提交 → 手势 / 定位
 * 不含答题、交卷、考试脱控
 * 桥：window.webkit.messageHandlers.ksnmsg（WKScriptMessageHandlerWithReply，postMessage 直接返回 Promise）
 */
(function () {
  "use strict";
  if (window.__KSN_IOS) return;
  window.__KSN_IOS = 1;

  var host = location.hostname || "";
  /* about:blank 上跑没有意义，只会把状态刷成 "Load failed" 噪音 */
  if (!host) return;
  if (!/chaoxing|superstar|course|ocs|welearn|xuexitong/i.test(host)) return;

  var API = {
    activelist: "https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist?fid=0&showNotStartedActive=0",
    signDetail: "https://mobilelearn.chaoxing.com/newsign/signDetail?clientip=&appType=15",
    stuSign:    "https://mobilelearn.chaoxing.com/pptSign/stuSignajax?&clientip=&appType=15&ifTiJiao=1&vpProbability=-1&vpStrategy=",
    faceUp:     "https://mobilelearn.chaoxing.com/v2/apis/sign/collectionfilephotoEnc?DB_STRATEGY=DEFAULT"
  };

  var H = (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ksnmsg) || null;
  var CFG = null, running = false, signedSet = {}, geoPatched = false, faceId = "";

  function call(cmd, args) {
    if (!H) return Promise.resolve(null);
    try {
      return Promise.resolve(H.postMessage({ cmd: cmd, args: args || {} }));
    } catch (e) {
      return Promise.resolve(null);
    }
  }
  function log(m)   { call("log", { m: String(m) }); }
  function state(m) { window.__ksn_state = String(m); call("state", { m: String(m) }); }

  /* 所有接口走原生 NSURLSession。
     WKWebView 的 fetch 会带不可控的存储策略和 UA，也拿不到全部 cookie，
     而且 WebView 里所有签到接口都返回 tengine 的 500 —— 直连才能分清是服务端还是通道。 */
  function netReq(url, method, body) {
    return call("net", { url: url, method: method || "GET", body: body || "" })
      .then(function (r) {
        if (r && typeof r === "object") return r;
        return { ok: false, status: 0, body: "", err: "桥无响应", ncookie: 0 };
      });
  }
  function brief(r) {
    var t = String((r && r.body) || "").replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
    return "HTTP " + ((r && r.status) || 0) +
           (r && r.ncookie != null ? " c" + r.ncookie : "") +
           (t ? " " + t.slice(0, 90) : (r && r.err ? " " + r.err : ""));
  }

  function loadCfg() {
    return call("cfg").then(function (c) {
      if (c && typeof c === "object") CFG = c;
      return CFG;
    });
  }
  function saveCfg(patch) {
    return call("savecfg", patch).then(function (c) {
      if (c && typeof c === "object") CFG = c;
      return CFG;
    });
  }

  /* ---------- 定位覆盖 ----------
     标准 GeolocationPosition 结构是 {coords:{latitude,longitude},timestamp}。
     原 Android 版直接回 {lat,lng}，页面读 coords.latitude 会拿到 undefined。 */
  function patchGeo() {
    if (geoPatched || !CFG || !CFG.mockLocation) return;
    var raw = CFG.locationRaw || "";
    if (!raw) return;
    var parts = raw.split(",");
    var lat = parseFloat(parts[0]), lng = parseFloat(parts[1]);
    if (isNaN(lat) || isNaN(lng)) { state("定位格式错误，应为 lat,lng,地址"); return; }

    function pos() {
      return {
        coords: { latitude: lat, longitude: lng, accuracy: 8,
                  altitude: null, altitudeAccuracy: null, heading: null, speed: null },
        timestamp: Date.now(),
        lat: lat, lng: lng
      };
    }
    var fake = {
      getCurrentPosition: function (ok) { try { ok(pos()); } catch (e) {} },
      watchPosition: function (ok) { try { ok(pos()); } catch (e) {} return 1; },
      clearWatch: function () {}, clearTimeout: function () {}
    };
    try {
      Object.defineProperty(navigator, "geolocation", { get: function () { return fake; }, configurable: true });
      geoPatched = true;
      state("定位已锁定 " + lat.toFixed(4) + "," + lng.toFixed(4));
    } catch (e) { log("geo 覆盖失败 " + e); }
  }

  /* ---------- 签到码 ---------- */
  function freshSignCode(apid) {
    return netReq(API.signDetail, "POST",
                  "activePrimaryId=" + encodeURIComponent(apid) + "&appType=15&msg=")
      .then(function (r) {
        if (!r.ok) { log("signDetail " + brief(r)); return call("signcode", {}); }
        var o;
        try { o = JSON.parse(r.body || "{}"); }
        catch (e) { return call("signcode", {}); }
        var c = (o && o.signCode) || (o && o.data && o.data.signCode) || "";
        if (c) { call("signcode", { c: c }); return c; }
        return call("signcode", {});
      })
      .then(function (c) { return typeof c === "string" ? c : ""; });
  }

  /* ---------- 活动列表 ---------- */
  function fetchActives() {
    return netReq(API.activelist, "GET").then(function (r) {
      if (!r.ok) return { recs: [], raw: brief(r) };
      var t = r.body || "";
      var j;
      try { j = JSON.parse(t); }
      catch (e) { return { recs: [], raw: "非JSON " + brief(r) }; }
      var recs = (j && j.records) || (j && j.data && j.data.records) || (j && j.data) || [];
      if (!Array.isArray(recs)) recs = (recs && recs.records) || [];
      return { recs: recs, raw: t };
    });
  }

  /* ---------- 人脸上传（可靠性低，只是把已存照片传上去换 faceCode） ---------- */
  function uploadFace() {
    if (faceId) return Promise.resolve(faceId);
    if (!CFG || !CFG.faceSign) return Promise.resolve("");
    return call("face").then(function (b64) {
      if (!b64 || String(b64).length < 1000) { log("没有已存人脸图"); return ""; }
      var bin = atob(b64);
      var buf = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
      var fd = new FormData();
      fd.append("file", new Blob([buf], { type: "image/jpeg" }), "face.jpg");
      return fetch(API.faceUp, {
        method: "POST", credentials: "include",
        headers: { "X-Requested-With": "XMLHttpRequest" },
        body: fd
      }).then(function (r) { return r.text(); })
        .then(function (t) {
          try { var o = JSON.parse(t); faceId = String(o.id || o.data || o.result || "").slice(0, 64); }
          catch (e) { faceId = ""; }
          log("face → " + t.slice(0, 60));
          return faceId;
        })
        .catch(function (e) { log("人脸上传失败 " + e); return ""; });
    });
  }

  /* ---------- 单项签到 ---------- */
  function signOne(item) {
    var apid = item.activePrimaryId || item.id;
    var cid  = item.courseId || item.cid;
    var clid = item.classId || item.classid;
    var st   = (item.signStatus != null) ? item.signStatus : item.status;
    if (!apid || !cid || Number(st) === 1 || signedSet[apid]) {
      log("skip apid=" + apid + " cid=" + cid + " st=" + st + " keys=" + Object.keys(item).join(","));
      return Promise.resolve(null);
    }

    return freshSignCode(String(apid)).then(function (code) {
      return uploadFace().then(function (fid) {
        var form = new URLSearchParams();
        form.set("courseId", String(cid));
        form.set("classId", String(clid || 0));
        form.set("activePrimaryId", String(apid));
        form.set("uid", String(item.uid || ""));
        form.set("appType", "15");
        form.set("isTeacherViewOpen", "0");
        form.set("clientip", "");
        form.set("vpProbability", "-1");
        form.set("vpStrategy", "");
        form.set("faceCode", fid || "");
        form.set("faceEncAid", fid || "");
        if (code) form.set("signCode", code);
        if (item.name) form.set("name", item.name);

        var locRaw = (CFG && CFG.mockLocation) ? (CFG.locationRaw || "") : "";
        if (locRaw) {
          var p = locRaw.split(",");
          var lat = (p[0] || "").trim(), lng = (p[1] || "").trim(), addr = (p[2] || "").trim();
          form.set("latitude", lat);
          form.set("longitude", lng);
          form.set("address", addr);
          /* URLSearchParams 会编码一次，这里不要再 encodeURIComponent，否则双重编码 */
          form.set("location", JSON.stringify({ result: 1, latitude: lat, longitude: lng, address: addr }));
        }

        return netReq(API.stuSign, "POST", form.toString())
          .then(function (r) {
            var t = (r && r.body) || "";
            signedSet[apid] = 1;
            log("签到 " + apid + " code=" + (code || "-") + " → " + brief(r));
            return { apid: apid, ok: !!(r && r.ok) && /success|成功/i.test(t), text: t };
          });
      });
    }).catch(function (e) {
      log("签到异常 " + apid + " " + e);
      return { apid: apid, ok: false, text: "" };
    });
  }

  /* ---------- 全量 ---------- */
  function signAll(trigger) {
    if (running) return Promise.resolve([]);
    running = true;
    var who = host || "blank";
    state("[" + who + "] 扫描中…");

    return loadCfg()
      .then(function () { patchGeo(); return fetchActives(); })
      .then(function (res) {
        if (!res.recs.length) return { total: 0, done: [], raw: res.raw };
        var done = [];
        return res.recs.reduce(function (chain, it) {
          return chain.then(function () {
            return signOne(it).then(function (r) { if (r) done.push(r); });
          });
        }, Promise.resolve()).then(function () {
          return { total: res.recs.length, done: done, raw: res.raw };
        });
      })
      .then(function (r) {
        if (!r.total) {
          state("[" + who + "] 列表空 → " + String(r.raw || "").slice(0, 110));
        } else if (!r.done.length) {
          state("[" + who + "] " + r.total + " 项全部跳过（已签或字段缺失）");
        } else {
          var ok = r.done.filter(function (x) { return x.ok; }).length;
          var msg = "提交 " + r.done.length + "/" + r.total + "，成功 " + ok;
          state("[" + who + "] " + msg);
          call("notify", { title: "签到", body: msg });
        }
        running = false;
        return r.done;
      })
      .catch(function (e) {
        state("[" + who + "] 失败 " + ((e && e.message) || e));
        running = false;
        return [];
      });
  }

  /* ---------- 手势 ---------- */
  var gestBound = false;
  function findPad() {
    var cv = document.querySelector("canvas");
    if (cv) return cv;
    var c = document.querySelectorAll("[class*=gesture],[class*=pattern],[class*=draw],[class*=swipe],#gestureArea,.sign-gesture");
    return c.length ? c[0] : null;
  }
  function normPoints(pts, w, h) {
    var out = [], step = Math.max(1, Math.floor(pts.length / 40));
    for (var i = 0; i < pts.length; i += step) {
      out.push([Math.round(pts[i * 2] / w * 1000), Math.round(pts[i * 2 + 1] / h * 1000)]);
    }
    return out;
  }
  function learnGesture() {
    var pad = findPad();
    if (!pad || gestBound) return;
    gestBound = true;
    var pts = [], rec = false, t0 = 0;
    function at(e) {
      var r = pad.getBoundingClientRect();
      return [e.clientX - r.left, e.clientY - r.top, r.width, r.height];
    }
    pad.addEventListener("pointerdown", function (e) {
      var p = at(e); t0 = Date.now(); pts = [p[0], p[1]]; rec = true;
    }, { capture: true });
    pad.addEventListener("pointermove", function (e) {
      if (!rec) return;
      var p = at(e); pts.push(p[0], p[1]);
    }, { capture: true });
    pad.addEventListener("pointerup", function (e) {
      if (!rec) return;
      rec = false;
      var p = at(e);
      var n = normPoints(pts, p[2] || 1, p[3] || 1);
      call("savegesture", { g: JSON.stringify({ t: Date.now() - t0, p: n }) });
      state("手势已记住 " + n.length + " 点");
    }, { capture: true });
  }
  function replayGesture() {
    return call("getgesture").then(function (g) {
      if (!g) return;
      var d;
      try { d = JSON.parse(g); } catch (e) { return; }
      if (!d || !d.p || !d.p.length) return;
      var pad = findPad();
      if (!pad) return;
      var r = pad.getBoundingClientRect();
      if (r.width < 40 || r.height < 40) return;
      var stepMs = Math.max(6, Math.min(40, (d.t || 600) / d.p.length));
      var i = 0;
      (function step() {
        if (i >= d.p.length) {
          var last = d.p[d.p.length - 1];
          try {
            pad.dispatchEvent(new PointerEvent("pointerup", {
              clientX: r.left + last[0] / 1000 * r.width,
              clientY: r.top + last[1] / 1000 * r.height,
              bubbles: true
            }));
          } catch (e) {}
          state("手势已重放");
          return;
        }
        var c = d.p[i];
        var cx = r.left + c[0] / 1000 * r.width;
        var cy = r.top + c[1] / 1000 * r.height;
        try {
          if (i === 0) pad.dispatchEvent(new PointerEvent("pointerdown", { clientX: cx, clientY: cy, bubbles: true }));
          pad.dispatchEvent(new PointerEvent("pointermove", { clientX: cx, clientY: cy, bubbles: true }));
        } catch (e) {}
        i++;
        setTimeout(step, stepMs);
      })();
    });
  }

  /* ---------- 主循环 ---------- */
  function tick() {
    return loadCfg().then(function (cfg) {
      if (!cfg) return;
      patchGeo();
      if (cfg.signNow) {
        return saveCfg({ signNow: false }).then(function () { return signAll("manual"); });
      }
      if (cfg.autoSign) return signAll("auto");
    }).catch(function () {});
  }

  setTimeout(function () { tick(); }, 1500);
  setInterval(function () { tick(); }, 15000);

  setInterval(function () {
    if (!CFG || !CFG.gestureSign) return;
    if (!findPad()) return;
    call("getgesture").then(function (g) { if (g) replayGesture(); else learnGesture(); });
  }, 4000);

  window.__ksnSignNow = function () { return signAll("manual"); };
  window.__ksnReload = function () { return loadCfg(); };
  log("引擎已挂载 host=" + host + " bridge=" + (H ? "ok" : "none"));
})();
