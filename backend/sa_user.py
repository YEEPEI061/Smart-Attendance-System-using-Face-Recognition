from flask import Blueprint, request, jsonify
import mysql.connector
from flask_bcrypt import Bcrypt
import os
from dotenv import load_dotenv

sa_user_bp = Blueprint('sa_user', __name__)
load_dotenv()
bcrypt = Bcrypt()

db_config = {
    'host': os.getenv('DB_HOST'),
    'port': os.getenv('DB_PORT'),
    'user': os.getenv('DB_USERNAME'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_DATABASE')
}

def get_db_connection():
    return mysql.connector.connect(
        host=db_config['host'],
        port=int(db_config['port']),
        user=db_config['user'],
        password=db_config['password'],
        database=db_config['database']
    )

def insert_log(conn, user_id, action_type, target_entity, target_id=None, description=None):
    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO logs (user_id, action_type, target_entity, target_id, description)
        VALUES (%s, %s, %s, %s, %s)
    """, (user_id, action_type, target_entity, target_id, description))
    conn.commit()
    cursor.close()

@sa_user_bp.route("/sa/users", methods=["GET"])
def get_users():
    search = request.args.get('search', '').lower()  # get search term, default empty
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    if search:
        # Filter users by name, email, role, auth_provider
        query = """
            SELECT id, username, email, role, auth_provider
            FROM users
            WHERE LOWER(username) LIKE %s
            OR LOWER(email) LIKE %s
            OR LOWER(role) LIKE %s
            OR LOWER(auth_provider) LIKE %s
            ORDER BY username ASC
        """
        like_pattern = f"%{search}%"
        cursor.execute(query, (like_pattern, like_pattern, like_pattern, like_pattern))
    else:
        # Return all users if no search
        cursor.execute("""
            SELECT id, username, email, role, auth_provider
            FROM users
            ORDER BY username ASC
        """)

    rows = cursor.fetchall()
    print("🟢 Rows fetched:", rows)

    cursor.close()
    conn.close()

    users = []
    for row in rows:
        users.append({
            "id": row["id"],
            "name": row["username"],
            "email": row["email"],
            "role": row["role"],
            "provider": row["auth_provider"]
        })

    return jsonify(users)


@sa_user_bp.route("/sa/user/delete", methods=["POST"])
def delete_user():
    data = request.json
    user_id_to_delete = data.get("user_id_to_delete")  # ID of the user to remove
    admin_id = data.get("admin_id")  # ID of the admin performing the action

    if not user_id_to_delete or not admin_id:
        return jsonify({"message": "Missing user_id_to_delete or admin_id"}), 400

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        # Get the name of the user to delete (for logs)
        cursor.execute("SELECT username FROM users WHERE id = %s", (user_id_to_delete,))
        user_row = cursor.fetchone()
        if not user_row:
            return jsonify({"message": "User not found"}), 404
        user_name = user_row["username"]

        # Delete in cascade order to satisfy all foreign key constraints:

        # 1) attendance records tied to this lecturer's classes
        cursor.execute("""
            DELETE a FROM attendance a
            JOIN classes c ON a.class_id = c.id
            JOIN subjects s ON c.subject_id = s.id
            WHERE s.lecturer_id = %s
        """, (user_id_to_delete,))

        # 2) classes tied to this lecturer's subjects
        cursor.execute("""
            DELETE c FROM classes c
            JOIN subjects s ON c.subject_id = s.id
            WHERE s.lecturer_id = %s
        """, (user_id_to_delete,))

        # 3) enrollments tied to this lecturer's subjects
        cursor.execute("""
            DELETE e FROM enrollments e
            JOIN subjects s ON e.subject_id = s.id
            WHERE s.lecturer_id = %s
        """, (user_id_to_delete,))

        # 4) subjects owned by this lecturer
        cursor.execute("DELETE FROM subjects WHERE lecturer_id = %s", (user_id_to_delete,))

        # 5) logs of the user
        cursor.execute("DELETE FROM logs WHERE user_id = %s", (user_id_to_delete,))

        # 6) finally delete the user
        cursor.execute("DELETE FROM users WHERE id = %s", (user_id_to_delete,))
        conn.commit()

        # Get admin name for log
        cursor.execute("SELECT username FROM users WHERE id = %s", (admin_id,))
        admin_row = cursor.fetchone()
        admin_name = admin_row["username"] if admin_row else f"Admin ID {admin_id}"

        # Insert log
        insert_log(
            conn=conn,
            user_id=admin_id,
            action_type="DELETE",
            target_entity="users",
            target_id=user_id_to_delete,
            description=f"{admin_name} deleted user {user_name}"
        )

        return jsonify({"message": f"User '{user_name}' deleted successfully"}), 200
    except Exception as e:
        print(f"[ERROR] Delete user failed: {e}")
        return jsonify({"message": "Failed to delete user"}), 500
    finally:
        if conn and conn.is_connected():
            cursor.close()
            conn.close()



@sa_user_bp.route("/sa/user/edit", methods=["POST"])
def edit_user():
    data = request.json
    user_id_to_edit = data.get("user_id_to_edit")  # The user being edited
    admin_id = data.get("admin_id")  # The admin performing the edit
    new_name = data.get("name")
    new_email = data.get("email")

    if not user_id_to_edit or not admin_id or not new_name or not new_email:
        return jsonify({"message": "Missing required fields"}), 400

    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        # Check if the user exists
        cursor.execute("SELECT username FROM users WHERE id = %s", (user_id_to_edit,))
        user_row = cursor.fetchone()
        if not user_row:
            return jsonify({"message": "User not found"}), 404

        old_name = user_row["username"]

        # Check if the new email is already used by another user
        cursor.execute(
            "SELECT id FROM users WHERE email = %s AND id != %s", 
            (new_email, user_id_to_edit)
        )
        if cursor.fetchone():
            return jsonify({"message": "Email already in use"}), 409

        # Update the user
        cursor.execute(
            "UPDATE users SET username = %s, email = %s WHERE id = %s",
            (new_name, new_email, user_id_to_edit)
        )
        conn.commit()

        # Get admin name for logging
        cursor.execute("SELECT username FROM users WHERE id = %s", (admin_id,))
        admin_row = cursor.fetchone()
        admin_name = admin_row["username"] if admin_row else f"Admin ID {admin_id}"

        # Insert log
        insert_log(
            conn=conn,
            user_id=admin_id,
            action_type="EDIT",
            target_entity="users",
            target_id=user_id_to_edit,
            description=f"{admin_name} edited user '{old_name}' to '{new_name}'"
        )

        return jsonify({"message": "User updated successfully"}), 200

    except Exception as e:
        print(f"[ERROR] Edit user failed: {e}")
        return jsonify({"message": "Failed to edit user"}), 500

    finally:
        if conn and conn.is_connected():
            cursor.close()
            conn.close()