import Foundation

// MARK: - 扫码上传页

/// 扫码上传页 — 单文件 HTML（内联 CSS/JS、无外部资源）
///
/// 页面只做一件事：把用户选择的文件逐个 `POST` 到 `/scan/upload`，并展示进度与结果。
/// token 由服务端校验后注入（32 位 hex，无注入风险），页面本身不携带业务状态。
public enum ScanPageRenderer {

    /// 渲染上传页 HTML
    public static func html(token: String) -> String {
        let safeToken = token.filter(\.isHexDigit)
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>局域网互传 · 扫码接收</title>
        <style>
        :root { color-scheme: light dark; --bg:#f5f5f7; --card:#ffffff; --text:#1d1d1f; --sub:#6e6e73; --accent:#0a84ff; --line:rgba(0,0,0,.10); --ok:#248a3d; --err:#d70015; }
        @media (prefers-color-scheme: dark) { :root { --bg:#000000; --card:#1c1c1e; --text:#f5f5f7; --sub:#98989d; --accent:#409cff; --line:rgba(255,255,255,.14); --ok:#30d158; --err:#ff453a; } }
        * { box-sizing: border-box; }
        body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center; background:var(--bg); color:var(--text); font:14px -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", sans-serif; }
        main { width:min(92vw, 420px); background:var(--card); border-radius:18px; padding:28px 24px; box-shadow:0 12px 40px rgba(0,0,0,.12); border:1px solid var(--line); }
        h1 { font-size:20px; line-height:1.3; margin:0 0 8px; }
        p.sub { margin:0; font-size:13px; line-height:1.5; color:var(--sub); }
        .drop { margin-top:20px; border:1.5px dashed var(--line); border-radius:14px; padding:24px 16px; text-align:center; transition:border-color .2s, background-color .2s; }
        .drop.over { border-color:var(--accent); background:rgba(10,132,255,.08); }
        .drop button { appearance:none; border:0; border-radius:10px; background:var(--accent); color:#fff; font-size:15px; font-weight:600; padding:10px 20px; cursor:pointer; }
        .drop button:active { opacity:.8; }
        input[type=file] { display:none; }
        .progress { height:8px; border-radius:4px; background:var(--line); overflow:hidden; margin:16px 0 8px; display:none; }
        .progress i { display:block; height:100%; width:0; background:var(--accent); transition:width .15s linear; }
        #status { font-size:13px; line-height:1.5; color:var(--sub); min-height:20px; word-break:break-all; }
        #list { list-style:none; margin:12px 0 0; padding:0; font-size:13px; }
        #list li { display:flex; justify-content:space-between; align-items:baseline; gap:10px; padding:7px 0; border-top:1px solid var(--line); }
        #list li:first-child { border-top:0; }
        #list .name { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; flex:1 1 auto; }
        #list .ok { color:var(--ok); flex:0 0 auto; }
        #list .err { color:var(--err); flex:0 0 auto; }
        </style>
        </head>
        <body>
        <main>
        <h1>局域网互传 · 扫码接收</h1>
        <p class="sub">把文件拖进下方区域，或点按钮选择。文件会直接传到这台 Mac。</p>
        <div class="drop" id="drop">
        <button type="button" id="pick">选择文件…</button>
        <p class="sub" style="margin:12px 0 0">或拖到此区域，支持多选</p>
        </div>
        <input type="file" id="file" multiple>
        <div class="progress" id="progress"><i></i></div>
        <div id="status"></div>
        <ul id="list"></ul>
        </main>
        <script>
        (function () {
          var TOKEN = '\(safeToken)';
          var drop = document.getElementById('drop');
          var pick = document.getElementById('pick');
          var input = document.getElementById('file');
          var progress = document.getElementById('progress');
          var bar = progress.querySelector('i');
          var status = document.getElementById('status');
          var list = document.getElementById('list');
          var queue = [];
          var busy = false;

          pick.addEventListener('click', function () { input.click(); });
          input.addEventListener('change', function () { enqueue(input.files); input.value = ''; });
          ['dragenter', 'dragover'].forEach(function (name) {
            drop.addEventListener(name, function (event) { event.preventDefault(); drop.classList.add('over'); });
          });
          ['dragleave', 'drop'].forEach(function (name) {
            drop.addEventListener(name, function (event) { event.preventDefault(); drop.classList.remove('over'); });
          });
          drop.addEventListener('drop', function (event) { enqueue(event.dataTransfer.files); });

          function enqueue(files) {
            if (!files) return;
            for (var i = 0; i < files.length; i++) queue.push(files[i]);
            pump();
          }

          function pump() {
            if (busy) return;
            var file = queue.shift();
            if (!file) return;
            upload(file);
          }

          function upload(file) {
            busy = true;
            progress.style.display = 'block';
            bar.style.width = '0%';
            status.textContent = '正在上传 ' + file.name + '…';
            if (file.size > 2147483648) {
              finishFile(file, '超过 2 GiB 上限', false);
              return;
            }
            var xhr = new XMLHttpRequest();
            xhr.open('POST', '/scan/upload?t=' + encodeURIComponent(TOKEN) + '&name=' + encodeURIComponent(file.name));
            xhr.setRequestHeader('Content-Type', 'application/octet-stream');
            xhr.upload.onprogress = function (event) {
              if (event.lengthComputable) bar.style.width = Math.round(event.loaded / event.total * 100) + '%';
            };
            xhr.onload = function () {
              var payload = null;
              try { payload = JSON.parse(xhr.responseText); } catch (error) { payload = null; }
              if (xhr.status === 200 && payload && payload.code === 0 && payload.data) {
                finishFile(file, '已保存为 ' + payload.data.savedAs, true);
              } else if (xhr.status === 413) {
                finishFile(file, '超过 2 GiB 上限', false);
              } else {
                finishFile(file, (payload && payload.message) ? payload.message : ('失败（HTTP ' + xhr.status + '）'), false);
              }
            };
            xhr.onerror = function () { finishFile(file, '网络错误', false); };
            xhr.send(file);
          }

          function finishFile(file, message, ok) {
            var row = document.createElement('li');
            var name = document.createElement('span');
            name.className = 'name';
            name.textContent = file.name;
            var state = document.createElement('span');
            state.className = ok ? 'ok' : 'err';
            state.textContent = message;
            row.appendChild(name);
            row.appendChild(state);
            list.appendChild(row);
            status.textContent = message;
            progress.style.display = 'none';
            bar.style.width = '0%';
            busy = false;
            pump();
          }
        })();
        </script>
        </body>
        </html>
        """
    }

    /// 响应头（HTML 页面固定 UTF-8）
    public static let contentType = "text/html; charset=utf-8"
}
