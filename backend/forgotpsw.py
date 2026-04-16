import os
import re
import secrets
import hashlib
import mysql.connector
from datetime import datetime, timedelta
from flask import Blueprint, request, jsonify
from flask_bcrypt import Bcrypt
from dotenv import load_dotenv
from brevo_sender import send_email

forgot_password_bp = Blueprint('forgot_password', __name__)
load_dotenv()
bcrypt = Bcrypt()


def get_db_connection():
    return mysql.connector.connect(
        host=os.getenv('DB_HOST'),
        port=int(os.getenv('DB_PORT', 3306)),
        user=os.getenv('DB_USERNAME'),
        password=os.getenv('DB_PASSWORD'),
        database=os.getenv('DB_DATABASE'),
    )


def is_strong_password(password: str) -> bool:
    """Validate password strength"""
    if len(password) < 8:
        return False
    if not re.search(r"[0-9]", password):
        return False
    if not re.search(r"[a-z]", password):
        return False
    if not re.search(r"[A-Z]", password):
        return False
    if not re.search(r"[^A-Za-z0-9]", password):
        return False
    return True


# SEND OTP
@forgot_password_bp.route('/forgot-password', methods=['POST'])
def forgot_password():

    data = request.get_json()

    if not data:
        return jsonify({'message': 'No data provided'}), 400

    email = (data.get('email') or '').strip().lower()

    if not email:
        return jsonify({'message': 'Please enter your email address'}), 400

    # Email format validation
    if not re.match(r"[^@]+@[^@]+\.[^@]+", email):
        return jsonify({'message': 'Invalid email format'}), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        # 1️⃣ Delete expired OTP
        cursor.execute("DELETE FROM password_reset_codes WHERE expires_at < NOW()")
        conn.commit()

        cursor.execute(
            "SELECT id FROM users WHERE email = %s",
            (email,)
        )

        user = cursor.fetchone()

        if not user:
            return jsonify({'message': 'Email not found'}), 404

        # Prevent requesting OTP too frequently (60 seconds)
        cursor.execute("""
        SELECT created_at FROM password_reset_codes
        WHERE email = %s
        ORDER BY created_at DESC
        LIMIT 1
        """, (email,))

        last_request = cursor.fetchone()

        if last_request:
            diff = datetime.now() - last_request['created_at']
            if diff.total_seconds() < 60:
                return jsonify({'message': 'Please wait before requesting another code'}), 429

        # 2️⃣ Ensure only ONE active OTP per user
        cursor.execute(
            "DELETE FROM password_reset_codes WHERE email = %s",
            (email,)
        )

        # Generate OTP
        code = ''.join(secrets.choice('0123456789') for _ in range(6))

        # Hash OTP
        code_hash = hashlib.sha256(code.encode()).hexdigest()

        expiry = datetime.now() + timedelta(minutes=5)

        # Store OTP
        cursor.execute("""
        INSERT INTO password_reset_codes
        (email, code_hash, expires_at)
        VALUES (%s, %s, %s)
        """, (email, code_hash, expiry))

        conn.commit()

        email_body = f"""
Hello,

You requested a password reset. Your verification code is:

{code}

This code will expire in 5 minutes. If you did not request this, please ignore this email.

Best regards,
Smart Attendance System
"""

        send_email(
            email,
            "Password Reset Verification Code",
            email_body
        )

        return jsonify({"message": "Verification code sent to your email"}), 200

    except Exception as e:
        print("Forgot password error:", e)
        return jsonify({'message': 'Server error'}), 500

    finally:
        if conn and conn.is_connected():
            if cursor:
                cursor.close()
            conn.close()


# RESET PASSWORD
@forgot_password_bp.route('/reset-password', methods=['POST'])
def reset_password():

    data = request.get_json() or {}

    email = (data.get('email') or '').lower().strip()
    code = (data.get('code') or '').strip()
    new_password = data.get('new_password') or ''

    if not email or not code or not new_password:
        return jsonify({'message': 'Missing email, code or password'}), 400

    if not is_strong_password(new_password):
        return jsonify({'message': 'Password must contain 8 characters, uppercase, lowercase, number and symbol'}), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        cursor.execute("""
        SELECT * FROM password_reset_codes
        WHERE email = %s
        ORDER BY created_at DESC
        LIMIT 1
        """, (email,))

        entry = cursor.fetchone()

        if not entry:
            return jsonify({'message': 'No reset request found'}), 404

        # Brute force protection
        if entry['attempts'] >= 5:
            return jsonify({'message': 'Too many attempts. Please request a new code.'}), 429

        # Expiry check
        if datetime.now() > entry['expires_at']:
            return jsonify({'message': 'Verification code expired'}), 400

        # Hash input OTP
        code_hash = hashlib.sha256(code.encode()).hexdigest()

        if code_hash != entry['code_hash']:

            cursor.execute("""
            UPDATE password_reset_codes
            SET attempts = attempts + 1
            WHERE id = %s
            """, (entry['id'],))

            conn.commit()

            return jsonify({'message': 'Invalid verification code'}), 400

        # Hash new password
        hashed_password = bcrypt.generate_password_hash(new_password).decode('utf-8')

        cursor.execute(
            "UPDATE users SET password = %s WHERE email = %s",
            (hashed_password, email)
        )

        # Delete OTP after successful reset
        cursor.execute(
            "DELETE FROM password_reset_codes WHERE email = %s",
            (email,)
        )

        conn.commit()

        return jsonify({"message": "Password reset successful"}), 200

    except Exception as e:
        print("Reset error:", e)
        return jsonify({'message': 'Failed to update password'}), 500

    finally:
        if conn and conn.is_connected():
            if cursor:
                cursor.close()
            conn.close()