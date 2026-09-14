const { query, queryOne } = require('../config/database');

/**
 * 用户服务（含三端角色）
 */
const userService = {
    async getAllUsers() {
        const rows = await query(
            `SELECT id, username, role, display_name, end_name, mine_id, created_at
             FROM users ORDER BY id`
        );
        return rows;
    },

    async getUserById(id) {
        return await queryOne(
            `SELECT id, username, role, display_name, end_name, mine_id, created_at
             FROM users WHERE id = $1`, [id]
        );
    },

    async findByUsername(username) {
        return await queryOne(
            `SELECT * FROM users WHERE username = $1`, [username]
        );
    },

    async createUser(data) {
        const rows = await query(
            `INSERT INTO users (username, password, role, display_name, end_name, mine_id)
             VALUES ($1, $2, $3, $4, $5, $6)
             RETURNING id, username, role, display_name, end_name, mine_id, created_at`,
            [data.username, data.password, data.role || 'enterprise', data.display_name, data.end_name, data.mine_id || null]
        );
        return rows[0];
    },

    async updateUser(id, data) {
        const sets = [];
        const params = [];
        const fields = { username: 'username', display_name: 'display_name', end_name: 'end_name', role: 'role', password: 'password' };
        Object.keys(fields).forEach((k) => {
            if (data[k] !== undefined) {
                params.push(data[k]);
                sets.push(`${fields[k]} = $${params.length}`);
            }
        });
        if (!sets.length) return null;
        params.push(id);
        const rows = await query(
            `UPDATE users SET ${sets.join(', ')} WHERE id = $${params.length}
             RETURNING id, username, role, display_name, end_name, mine_id, created_at`,
            params
        );
        return rows[0] || null;
    },

    async deleteUser(id) {
        const rows = await query(`DELETE FROM users WHERE id = $1 RETURNING id`, [id]);
        return rows.length > 0;
    }
};

module.exports = userService;
