/**
 * WebSocket 广播中枢
 * 负责把实时数据推送给所有已连接客户端（PC 三端 + 鸿蒙移动端）
 */
let broadcastFn = null;

function setBroadcast(fn) {
    broadcastFn = fn;
}

function emit(type, payload) {
    if (broadcastFn) broadcastFn(type, payload);
}

module.exports = { setBroadcast, emit };
