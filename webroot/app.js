/* 原生桥签名依据 KernelSU 官方 js/index.js；只调用固定入口和白名单参数。 */
(() => {
  'use strict';
  const root = document.getElementById('hyperloghush');
  const rules = window.HUSH_RULES;
  const groups = window.HUSH_GROUPS;
  const tags = new Set(rules.map(rule => rule.tag));
  const preview = new URLSearchParams(location.search).get('preview') === '1';
  const notice = root.querySelector('#hush-notice');
  const refresh = root.querySelector('#hush-refresh');
  const controls = new Map();
  let busy = false;
  let sequence = 0;
  let snapshot = null;
  const demo = { schema: 1, diagnostic: false, rows: rules.map(rule => ({ tag: rule.tag, choice: 'warn', source: 'module', level: 'W' })) };

  function message(text, error = false) {
    notice.textContent = text;
    notice.classList.toggle('error', error);
  }

  function setBusy(value) {
    busy = value;
    root.setAttribute('aria-busy', String(value));
    refresh.disabled = value;
    for (const control of controls.values()) {
      for (const button of control.buttons) button.disabled = value || snapshot === null;
    }
  }

  function validate(data) {
    if (data?.schema !== 1 || typeof data.diagnostic !== 'boolean' || !Array.isArray(data.rows) || data.rows.length !== tags.size) throw new Error('状态格式不兼容，请核对模块版本。');
    const seen = new Set();
    for (const row of data.rows) {
      if (!tags.has(row.tag) || seen.has(row.tag) || !['warn', 'default'].includes(row.choice) || !['module', 'external', 'persistent', 'inherited', 'pending'].includes(row.source) || !['', 'V', 'D', 'I', 'W', 'E', 'F', 'S', '?'].includes(row.level)) throw new Error('状态校验失败，未启用操作。');
      seen.add(row.tag);
    }
    return data;
  }

  function render(data) {
    snapshot = validate(data);
    let active = 0;
    const sources = { module: '本模块', external: '外部临时设置', persistent: '外部持久设置', inherited: '系统继承', pending: '恢复记录待核对' };
    for (const row of data.rows) {
      const control = controls.get(row.tag);
      const managed = row.source === 'module' && row.level === 'W';
      if (managed) active++;
      const level = row.level === 'W' ? 'WARN' : (row.level || '组件默认');
      control.state.textContent = `${sources[row.source]} · ${level}${row.choice === 'default' && managed ? ' · 恢复未完成' : ''}`;
      control.state.classList.toggle('active', managed);
      if (row.source === 'pending' || (row.choice === 'default' && managed)) {
        setResult(row.tag, '未完成：设置或恢复待重试', 'error');
      } else if (row.choice === 'default') {
        setResult(row.tag, '已恢复默认：本模块未控制该项', 'success');
      } else if (managed) {
        setResult(row.tag, '设置成功：已读回 WARN', 'success');
      } else if (['external', 'persistent'].includes(row.source) || ['W', 'E', 'F', 'S', '?'].includes(row.level)) {
        setResult(row.tag, '未执行：受外部或全局设置保护', 'warning');
      } else {
        setResult(row.tag, '未应用：尚未确认 WARN 设置', 'warning');
      }
      for (const button of control.buttons) button.setAttribute('aria-pressed', String(button.dataset.action === row.choice));
    }
    root.querySelector('#hush-count').textContent = `${active} / ${tags.size}`;
    root.querySelector('#hush-mode').textContent = `仅本次开机有效 · 重启${data.diagnostic ? '回到全局诊断模式' : '恢复默认降噪'}`;
  }

  function setResult(tag, text, kind) {
    const result = controls.get(tag).result;
    result.textContent = text;
    result.dataset.kind = kind;
  }

  function execute(action, tag) {
    if (!['status', 'warn', 'default'].includes(action) || (action !== 'status' && !tags.has(tag))) return Promise.reject(new Error('拒绝非白名单操作。'));
    if (preview) {
      if (action !== 'status') Object.assign(demo.rows.find(row => row.tag === tag), { choice: action, source: action === 'warn' ? 'module' : 'inherited', level: action === 'warn' ? 'W' : '' });
      return Promise.resolve({ errno: 0, stdout: JSON.stringify(demo) });
    }
    if (!window.ksu || typeof window.ksu.exec !== 'function') return Promise.reject(new Error('请从 KernelSU 管理器打开。浏览器不能控制设备。'));
    // 两层超时：设备命令 15 秒；桥响应 20 秒，不盲目重发写入。
    const command = `PATH=/data/adb/ksu/bin:/system/bin ASH_STANDALONE=1 /data/adb/ksu/bin/busybox timeout 15 /data/adb/ksu/bin/busybox ash /data/adb/modules/luna_log_filter/control.sh ${action}${tag ? ` '${tag}'` : ''}`;
    return new Promise((resolve, reject) => {
      const callback = `hush_callback_${Date.now()}_${sequence++}`;
      const timer = setTimeout(() => {
        delete window[callback];
        reject(new Error('操作超时，结果未知。请刷新核对，勿连续重试。'));
      }, 20000);
      window[callback] = (errno, stdout, stderr) => {
        clearTimeout(timer);
        delete window[callback];
        resolve({ errno, stdout, stderr });
      };
      try { window.ksu.exec(command, '{}', callback); }
      catch (error) { clearTimeout(timer); delete window[callback]; reject(error); }
    });
  }

  async function run(action, tag) {
    if (busy) return;
    setBusy(true);
    message(action === 'status' ? '正在读取状态…' : '正在应用并核对…');
    if (tag) setResult(tag, '正在执行…', 'pending');
    let confirmed = false;
    let returned = false;
    try {
      const result = await execute(action, tag);
      returned = true;
      if (result.stdout) { render(JSON.parse(result.stdout)); confirmed = true; }
      else throw new Error('未收到完整状态，请刷新核对。');
      if (Number(result.errno) !== 0) throw new Error('操作未完全成功：可能存在外部覆盖、并发操作或写入失败。请刷新核对。');
      const row = snapshot.rows.find(item => item.tag === tag);
      if (tag) {
        const matches = action === 'warn'
          ? row.choice === 'warn' && row.source === 'module' && row.level === 'W'
          : row.choice === 'default' && !['module', 'pending'].includes(row.source);
        if (!matches) throw new Error('操作返回成功，但逐项状态未满足请求，请刷新核对。');
        setResult(tag, action === 'warn' ? '执行成功：已设置并读回 WARN' : '执行成功：已恢复默认', 'success');
      }
      if (row?.choice === 'default' && ['external', 'persistent'].includes(row.source)) {
        message('已撤销本模块控制；该项仍由外部设置控制。');
      } else {
        message(preview ? '交互预览 · 模拟数据，不连接手机' : (action === 'status' ? '状态已读取 · 保留 WARN / ERROR / FATAL' : '已应用 · 仅本次开机有效'));
      }
    } catch (error) {
      // 失败后禁止用旧快照继续写入，必须先完成一次只读刷新。
      snapshot = null;
      if (!confirmed) {
        for (const [rowTag, control] of controls) {
          control.state.textContent = '状态待刷新';
          control.state.classList.remove('active');
          setResult(rowTag, '结果未知：请刷新核对', 'warning');
          for (const button of control.buttons) button.setAttribute('aria-pressed', 'false');
        }
        root.querySelector('#hush-count').textContent = `— / ${tags.size}`;
      }
      if (tag) {
        const detail = confirmed
          ? (controls.get(tag).result.dataset.kind === 'success' ? '当前属性已更新，但命令返回失败，请刷新核对' : controls.get(tag).result.textContent)
          : '请刷新核对';
        setResult(tag, `${returned && confirmed ? '执行失败或未完成' : '结果未知'}：${detail}`, 'error');
      }
      message(error instanceof Error ? error.message : '读取失败，请刷新核对。', true);
    } finally { setBusy(false); }
  }

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;
    return node;
  }

  groups.forEach((group, index) => {
    const members = rules.filter(rule => rule.group === group.id);
    const section = element('section', 'group');
    const header = element('div', 'group-header');
    const title = element('h2', '', '');
    title.append(element('span', 'group-index', `0${index + 1}`), document.createTextNode(group.title), element('span', 'group-count', `${members.length} 项`));
    header.append(title, element('p', 'group-note', group.note));
    section.append(header);
    members.forEach((rule, memberIndex) => {
      const article = element('article', 'rule');
      const name = element('h3', '', rule.tag);
      name.id = `hush-rule-${index}-${memberIndex}`;
      const bottom = element('div', 'rule-bottom');
      const state = element('span', 'rule-state', '尚未读取');
      const result = element('p', 'rule-result', '尚未检查');
      result.setAttribute('role', 'status');
      const choices = element('div', 'choices');
      choices.setAttribute('role', 'group');
      choices.setAttribute('aria-labelledby', name.id);
      const buttons = [['warn', '开降噪'], ['default', '恢复默认']].map(([action, label]) => {
        const button = element('button', '', label);
        button.type = 'button';
        button.dataset.action = action;
        button.setAttribute('aria-pressed', 'false');
        button.disabled = true;
        button.addEventListener('click', () => run(action, rule.tag));
        choices.append(button);
        return button;
      });
      controls.set(rule.tag, { buttons, state, result });
      bottom.append(state, choices);
      article.append(name, element('p', 'description', rule.description), bottom, result);
      section.append(article);
    });
    root.querySelector('#hush-groups').append(section);
  });
  refresh.addEventListener('click', () => run('status'));
  run('status');
})();
