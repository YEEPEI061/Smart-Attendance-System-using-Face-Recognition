from flask import Blueprint, jsonify, request
import requests
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

def remove_faces_from_facepp(face_tokens):
    url = os.getenv("FACESET_REMOVE_URL")

    payload = {
        "api_key": os.getenv("FACEPP_API_KEY"),
        "api_secret": os.getenv("FACEPP_API_SECRET"),
        "faceset_token": os.getenv("FACESET_TOKEN"),
        "face_tokens": ",".join(face_tokens)
    }

    try:
        response = requests.post(url, data=payload)
        result = response.json()

        print("Face++ remove response:", result)

        # ✅ Check success
        if "error_message" in result:
            print("Face++ ERROR:", result["error_message"])
            return False

        return True

    except Exception as e:
        print("Face++ error:", e)
        return False


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


@update_student_bp.route("/students/<int:student_id>", methods=["DELETE"])
def delete_student(student_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        # 🔹 1. Get face tokens
        cursor.execute("""
            SELECT face_token 
            FROM student_faces 
            WHERE student_id = %s
        """, (student_id,))
        faces = cursor.fetchall()

        face_tokens = [f['face_token'] for f in faces if f.get('face_token')]

        # 🔹 2. Remove from Face++
        if face_tokens:
            result = remove_faces_from_facepp(face_tokens)
            if not result:
                return jsonify({"error": "Face++ deletion failed"}), 500

        # 🔹 3. Delete faces from DB
        cursor.execute("""
            DELETE FROM student_faces 
            WHERE student_id = %s
        """, (student_id,))

        # 🔹 4. Delete student
        cursor.execute("""
            DELETE FROM students 
            WHERE id = %s
        """, (student_id,))

        conn.commit()

        return jsonify({"message": "Student deleted successfully"}), 200

    except Exception as e:
        print(f"[ERROR] Delete student failed: {e}", flush=True)
        return jsonify({"error": str(e)}), 500

    finally:
        if cursor:
            cursor.close()
        if conn and conn.is_connected():
            conn.close()