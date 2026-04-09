from flask import Blueprint, jsonify, request
import mysql.connector
import os
from dotenv import load_dotenv
from flask import request

update_student_bp = Blueprint('update_student', __name__, url_prefix="/update")
load_dotenv()

db_config = {
    'host': os.getenv('DB_HOST'),
    'port': os.getenv('DB_PORT'),
    'user': os.getenv('DB_USERNAME'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_DATABASE')
}


BASE_URL = os.environ.get("BASE_URL", "")

def get_db_connection():
    return mysql.connector.connect(**db_config)

@update_student_bp.route("/students", methods=["GET"])
def get_students():
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        # 🔹 1. Get students (with PRIMARY image)
        cursor.execute("""
            SELECT 
                s.id,
                s.name,
                s.student_card_id,
                s.course_id,
                c.short_name AS course,
                s.face_image_url
            FROM students s
            LEFT JOIN courses c ON s.course_id = c.id
            ORDER BY s.name ASC
        """)

        students = cursor.fetchall()

        # 🔹 2. Get ALL faces (multiple per student)
        cursor.execute("""
            SELECT 
                student_id,
                face_image_url,
                is_primary
            FROM student_faces
            ORDER BY is_primary DESC, id ASC
        """)

        faces = cursor.fetchall()

        # 🔹 3. Group faces by student_id
        face_map = {}

        for f in faces:
            sid = f["student_id"]
            url = f["face_image_url"]

            if url:
                image_path = str(url).replace("\\", "/").lstrip("/")
                full_url = f"{BASE_URL.rstrip('/')}/{image_path}"
            else:
                full_url = None

            if sid not in face_map:
                face_map[sid] = []

            if full_url:
                face_map[sid].append(full_url)

        # 🔹 4. Attach faces + fix primary image URL
        for s in students:
            # primary image
            if s.get("face_image_url"):
                image_path = str(s["face_image_url"]).replace("\\", "/").lstrip("/")
                s["face_image_url"] = f"{BASE_URL.rstrip('/')}/{image_path}"

            # all faces
            s["faces"] = face_map.get(s["id"], [])

        return jsonify(students), 200

    except Exception as e:
        print(f"[ERROR] Fetch students failed: {e}", flush=True)
        return jsonify({"error": str(e)}), 500

    finally:
        if cursor:
            cursor.close()
        if conn and conn.is_connected():
            conn.close()