from flask import Blueprint, jsonify, request
import mysql.connector
import os
from dotenv import load_dotenv
from datetime import datetime

attendance_bp = Blueprint('attendance', __name__)
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

@attendance_bp.route("/attendance/taken", methods=["GET"])
def attendance_taken_today():
    """
    REMARK:
    - Returns whether attendance has been taken today for the given class_id.
    - Used by the mobile app to decide whether to show / schedule the
      "10 minutes before class ends" notification.
    """
    try:
        class_id = request.args.get("class_id", type=int)
        if not class_id:
            return jsonify({"error": "class_id is required"}), 400

        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        cursor.execute(
            """
            SELECT COUNT(*) AS cnt
            FROM attendance
            WHERE class_id = %s
              AND DATE(date) = CURDATE()
            """,
            (class_id,),
        )
        row = cursor.fetchone() or {}
        cnt = int(row.get("cnt") or 0)

        return jsonify({"taken": cnt > 0, "count": cnt}), 200

    except Exception as e:
        print(f"[ERROR] Attendance taken check failed: {e}", flush=True)
        return jsonify({"error": str(e)}), 500

    finally:
        if "conn" in locals() and conn and conn.is_connected():
            cursor.close()
            conn.close()

@attendance_bp.route("/attendance", methods=["GET"])
def get_attendance():
    conn = None
    cursor = None
    try:
        class_id = request.args.get("class_id", type=int)
        if not class_id:
            return jsonify({"error": "class_id is required"}), 400

        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        # Find the subject for this class
        cursor.execute("SELECT subject_id FROM classes WHERE id = %s", (class_id,))
        class_row = cursor.fetchone()
        if not class_row:
            return jsonify({"error": "Class not found"}), 404
        subject_id = class_row["subject_id"]

        # Fetch students enrolled in this subject with attendance for today
        cursor.execute("""
            SELECT 
                COALESCE(a.id, CONCAT('student_', s.id)) AS id,
                s.id AS student_id,
                s.name,
                s.student_card_id,
                c.short_name AS course,
                s.face_image_url,
                DATE_FORMAT(a.created_at, '%h:%i %p') AS time,
                a.date,
                COALESCE(a.status, 'Absent') AS status
            FROM enrollments e
            JOIN students s ON e.student_id = s.id
            LEFT JOIN courses c ON s.course_id = c.id
            LEFT JOIN attendance a 
                ON s.id = a.student_id 
                AND a.class_id = %s
                AND DATE(a.date) = CURDATE()
            WHERE e.subject_id = %s
            ORDER BY 
                CASE 
                    WHEN COALESCE(a.status, 'Absent') = 'Present' THEN 1
                    ELSE 2
                END,
                s.name ASC
        """, (class_id, subject_id))

        records = cursor.fetchall()

        for r in records:
            if r.get("face_image_url"):
                image_path = str(r["face_image_url"]).replace("\\", "/").lstrip("/")
                r["face_image_url"] = f"{request.host_url.rstrip('/')}/{image_path}"

        print("[DEBUG] Attendance records:", records, flush=True)

        return jsonify(records), 200

    except Exception as e:
        print(f"[ERROR] Fetch attendance failed: {e}", flush=True)
        return jsonify({"error": str(e)}), 500

    finally:
        if cursor:
            cursor.close()
        if conn and conn.is_connected():
            conn.close()

@attendance_bp.route("/attendance/manual", methods=["POST"])
def mark_manual():
    conn = None
    cursor = None
    try:
        data = request.get_json()

        class_id = data.get("class_id")
        student_id = data.get("student_id")
        status = data.get("status", "Present")
        today = datetime.now().date()

        if not class_id or not student_id:
            return jsonify({"error": "class_id and student_id are required"}), 400

        status = status.strip().capitalize()
        if status not in ["Present", "Absent"]:
            return jsonify({"error": "Invalid status. Must be Present or Absent"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()

        query = """
            INSERT INTO attendance (class_id, student_id, date, status)
            VALUES (%s, %s, %s, %s)
            ON DUPLICATE KEY UPDATE status = VALUES(status)
        """
        cursor.execute(query, (class_id, student_id, today, status))

        update_subject_query = """
            UPDATE subjects 
            SET updated_at = NOW() 
            WHERE id = (SELECT subject_id FROM classes WHERE id = %s)
        """
        cursor.execute(update_subject_query, (class_id,))

        conn.commit()

        return jsonify({
            "message": f"Attendance updated to {status}",
            "status": status
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()
        print(f"[ERROR] Manual attendance update failed: {e}", flush=True)
        return jsonify({"error": str(e)}), 500

    finally:
        if cursor:
            cursor.close()
        if conn and conn.is_connected():
            conn.close()

@attendance_bp.route("/attendance/summary", methods=["GET"])
def get_attendance_summary():
    try:
        class_id = request.args.get("class_id", type=int)
        if not class_id:
            return jsonify({"error": "class_id is required"}), 400

        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        # Get subject for this class
        cursor.execute("SELECT subject_id FROM classes WHERE id = %s", (class_id,))
        class_row = cursor.fetchone()
        if not class_row:
            return jsonify({"error": "Class not found"}), 404
        subject_id = class_row["subject_id"]

        # Count how many students are enrolled in this subject
        cursor.execute("""
            SELECT COUNT(*) AS total_students
            FROM enrollments e
            WHERE e.subject_id = %s
        """, (subject_id,))
        total_row = cursor.fetchone()
        total_students = total_row["total_students"]

        # Count how many are present today for this class
        cursor.execute("""
            SELECT COUNT(DISTINCT a.student_id) AS present_count
            FROM attendance a
            JOIN enrollments e ON a.student_id = e.student_id
            WHERE a.class_id = %s
              AND DATE(a.date) = CURDATE()
              AND e.subject_id = %s
              AND LOWER(a.status) = 'present'
        """, (class_id, subject_id))
        present_row = cursor.fetchone()
        present_count = present_row["present_count"]

        # Absent = total - present
        absent_count = total_students - present_count

        print(f"[DEBUG] Subject {subject_id}: total={total_students}, present={present_count}, absent={absent_count}", flush=True)

        return jsonify({
            "present_count": int(present_count or 0),
            "absent_count": int(absent_count if absent_count >= 0 else 0)
        }), 200

    except Exception as e:
        print(f"[ERROR] Attendance summary: {e}", flush=True)
        return jsonify({"error": "Failed to fetch summary"}), 500

    finally:
        if 'conn' in locals() and conn.is_connected():
            cursor.close()
            conn.close()


@attendance_bp.route('/attendance/<int:attendance_id>', methods=['DELETE'])
def delete_attendance(attendance_id):
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Delete the record from the 'attendance' table
        cursor.execute("DELETE FROM attendance WHERE id = %s", (attendance_id,))
        if cursor.rowcount == 0:
            conn.rollback()
            return jsonify({'message': 'Record not found'}), 404

        conn.commit()

        return jsonify({'message': 'Attendance record deleted successfully'}), 200

    except Exception as e:
        print(f"Error deleting attendance: {e}")
        return jsonify({'message': str(e)}), 500
    finally:
        if conn and conn.is_connected():
            cursor.close()
            conn.close()


@attendance_bp.route('/enrollments/<int:student_id>/<int:class_id>', methods=['DELETE'])
def delete_enrollment(student_id, class_id):
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT subject_id FROM classes WHERE id = %s", (class_id,))
        class_row = cursor.fetchone()
        if not class_row:
            return jsonify({'message': 'Class not found'}), 404
        subject_id = class_row[0]

        cursor.execute("""
            DELETE FROM enrollments
            WHERE student_id = %s AND subject_id = %s
        """, (student_id, subject_id))
        conn.commit()

        if cursor.rowcount == 0:
            return jsonify({'message': 'Enrollment not found'}), 404

        return jsonify({'message': 'Student removed from class successfully'}), 200

    except Exception as e:
        print(f"Error deleting enrollment: {e}", flush=True)
        if conn:
            conn.rollback()
        return jsonify({'message': str(e)}), 500

    finally:
        if conn and conn.is_connected():
            cursor.close()
            conn.close()