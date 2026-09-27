const express = require('express');
const udpController = require('../controllers/udp.controller');

const router = express.Router();

// VR 虚拟端↔硬件双向 UDP 转发（前端经 HTTP 交后端转发）
router.post('/forward', udpController.forward);

module.exports = router;