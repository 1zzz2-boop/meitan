const express = require('express');
const router = express.Router();
const authController = require('../controllers/auth.controller');

router.get('/captcha', authController.captcha);
router.post('/login', authController.login);
router.post('/register', authController.register);
router.post('/change-password', authController.changePassword);

module.exports = router;
