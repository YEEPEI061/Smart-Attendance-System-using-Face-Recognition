from flask import Blueprint, request, jsonify
import mysql.connector
import requests
import os
from dotenv import load_dotenv
from datetime import date
from PIL import Image

recognize_bp = Blueprint('recognize', __name__)
load_dotenv()

# Face++ credentials
FACEPP_API_KEY = os.getenv("FACEPP_API_KEY")
FACEPP_API_SECRET = os.getenv("FACEPP_API_SECRET")
DETECT_URL = os.getenv("DETECT_URL")
SEARCH_URL = os.getenv("SEARCH_URL")
FACESET_TOKEN = os.getenv("FACESET_TOKEN")

# Database config
db_config = {
    'host': os.getenv('DB_HOST'),
    'port': int(os.getenv('DB_PORT')),
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

@recognize_bp.route("/recognize", methods=["POST"])
def recognize_face():

    images = request.files.getlist("images")
    if not images:
        return jsonify({"error": "No images uploaded"}), 400

    class_id = request.form.get("class_id")
    if not class_id:
        return jsonify({"error": "No class_id provided"}), 400

    try:
        class_id = int(class_id)
    except ValueError:
        return jsonify({"error": "Invalid class_id"}), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        all_results = []
        processed_students = set()   # prevent duplicates
        total_marked = 0
        duplicates_skipped = 0

        for index, image in enumerate(images):

            os.makedirs("uploads", exist_ok=True)
            temp_path = f"uploads/temp_{index}.jpg"
            image.save(temp_path)

            # Resize
            img = Image.open(temp_path)
            img.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
            img.save(temp_path, format="JPEG", quality=85)

            # Detect
            with open(temp_path, "rb") as img_file:
                detect_res = requests.post(
                    DETECT_URL,
                    data={
                        "api_key": FACEPP_API_KEY,
                        "api_secret": FACEPP_API_SECRET
                    },
                    files={"image_file": img_file}
                )
                detect_data = detect_res.json()

            if "faces" not in detect_data or not detect_data["faces"]:
                continue

            for face in detect_data["faces"]:

                face_token = face["face_token"]

                search_res = requests.post(
                    SEARCH_URL,
                    data={
                        "api_key": FACEPP_API_KEY,
                        "api_secret": FACEPP_API_SECRET,
                        "faceset_token": FACESET_TOKEN,
                        "face_token": face_token
                    }
                )
                search_data = search_res.json()

                print("===== FACE++ SEARCH RESPONSE =====")
                print(search_data)
                print("=================================")

                if "results" not in search_data or not search_data["results"]:
                    continue

                match = search_data["results"][0]
                matched_token = match["face_token"]
                confidence = match["confidence"]

                if confidence < 70:
                    continue

                cursor.execute("""
                    SELECT s.id, s.name, co.short_name AS course
                    FROM students s
                    JOIN student_faces sf ON s.id = sf.student_id
                    JOIN enrollments e ON s.id = e.student_id
                    JOIN classes cl ON e.subject_id = cl.subject_id
                    LEFT JOIN courses co ON s.course_id = co.id
                    WHERE sf.face_token = %s
                    AND cl.id = %s
                """, (matched_token, class_id))

                student = cursor.fetchone()
                if not student:
                    continue

                student_id = student["id"]

                # 🚨 CHECK IF ALREADY PROCESSED IN THIS REQUEST
                if student_id in processed_students:
                    duplicates_skipped += 1
                    continue

                # Check DB attendance today
                cursor.execute("""
                    SELECT id FROM attendance
                    WHERE class_id = %s
                    AND student_id = %s
                    AND DATE(date) = %s
                """, (class_id, student_id, date.today()))

                existing = cursor.fetchone()

                if existing:
                    duplicates_skipped += 1
                    processed_students.add(student_id)
                    continue

                # Insert attendance
                cursor.execute("""
                    INSERT INTO attendance (class_id, student_id, date, status)
                    VALUES (%s, %s, %s, 'present')
                """, (class_id, student_id, date.today()))
                conn.commit()

                total_marked += 1
                processed_students.add(student_id)

                all_results.append({
                    "id": student_id,
                    "name": student["name"],
                    "course": student["course"],
                    "confidence": confidence
                })

        return jsonify({
            "total_students_marked": total_marked,
            "duplicates_skipped": duplicates_skipped,
            "recognized_students": all_results
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if cursor:
            cursor.close()
        if conn and conn.is_connected():
            conn.close()
