from flask import Blueprint, request, jsonify
import mysql.connector
import os
from dotenv import load_dotenv
from datetime import datetime, timedelta

load_dotenv()

reports_bp = Blueprint('reports_bp', __name__)

db_config = {
    'host': os.getenv('DB_HOST'),
    'port': os.getenv('DB_PORT'),
    'user': os.getenv('DB_USERNAME'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_DATABASE'),
}

def get_db_connection():
    return mysql.connector.connect(
        host=db_config['host'],
        port=int(db_config['port']),
        user=db_config['user'],
        password=db_config['password'],
        database=db_config['database'],
    )

@reports_bp.route('/api/subjects', methods=['GET'])
def get_subjects():
    user_id = request.args.get('user_id')
    if not user_id:
        return jsonify({"error": "User ID is required"}), 400
    
    db = get_db_connection()
    cursor = db.cursor(dictionary=True)
    try:
        query = "SELECT id, code, name FROM subjects WHERE lecturer_id = %s"
        cursor.execute(query, (user_id,))
        subjects = cursor.fetchall()
        return jsonify(subjects)
    finally:
        cursor.close()
        db.close()

@reports_bp.route('/api/subjects/<int:subject_id>/files', methods=['GET'])
def get_subject_files(subject_id):
    db = get_db_connection()
    cursor = db.cursor(dictionary=True)
    try:
        cursor.execute("SELECT id, schedule FROM classes WHERE subject_id = %s", (subject_id,))
        files = cursor.fetchall()
        return jsonify(files), 200
    finally:
        cursor.close()
        db.close()

@reports_bp.route('/api/reports', methods=['GET'])
def get_report():
    subject_id_arg = request.args.get('subject_id')
    class_id = request.args.get('class_id')
    selected_date_str = request.args.get('date')

    db = get_db_connection()
    cursor = db.cursor(dictionary=True)

    try:
        # Resolve subject_id
        if class_id:
            cursor.execute("SELECT subject_id FROM classes WHERE id = %s", (class_id,))
            row = cursor.fetchone()
            subject_id = row['subject_id'] if row else None
        else:
            subject_id = subject_id_arg

        if not subject_id:
            return jsonify({"error": "Subject or Class ID required"}), 400

        # Total Enrolled
        cursor.execute(
            "SELECT COUNT(*) as total FROM enrollments WHERE subject_id = %s",
            (subject_id,),
        )
        total_enrolled = cursor.fetchone()['total'] or 0

        # Overall Average Rate (Since Start)
        cursor.execute("""
            SELECT 
                COUNT(CASE WHEN a.status = 'present' THEN 1 END) as total_presents,
                COUNT(DISTINCT a.date, a.class_id) as total_sessions
            FROM attendance a
            JOIN classes c ON a.class_id = c.id
            WHERE c.subject_id = %s
        """, (subject_id,))
        overall_stats = cursor.fetchone()
        total_sessions_all_time = overall_stats['total_sessions'] or 0
        total_possible_spots = total_enrolled * total_sessions_all_time
        avg_rate_val = (
            round((overall_stats['total_presents'] / total_possible_spots) * 100, 1)
            if total_possible_spots > 0 else 0.0
        )

        # Daily Rate & Total Present (Selected Date)
        if class_id:
            cursor.execute(
                "SELECT COUNT(*) as count FROM attendance WHERE class_id = %s AND date = %s AND status = 'present'",
                (class_id, selected_date_str),
            )
            present_today = cursor.fetchone()['count'] or 0
            daily_rate = round((present_today / total_enrolled) * 100, 1) if total_enrolled > 0 else 0
        else:
            cursor.execute("""
                SELECT COUNT(CASE WHEN a.status='present' THEN 1 END) as p_count,
                       COUNT(DISTINCT class_id) as s_count
                FROM attendance a
                JOIN classes c ON a.class_id = c.id
                WHERE c.subject_id = %s AND a.date = %s
            """, (subject_id, selected_date_str))
            res = cursor.fetchone()
            present_today = res['p_count'] or 0
            s_count = res['s_count'] or 0
            total_possible_today = total_enrolled * s_count
            daily_rate = round((present_today / total_possible_today) * 100, 1) if total_possible_today > 0 else 0

        # Weekly Change Logic
        target_date_obj = datetime.strptime(selected_date_str, '%Y-%m-%d').date()

        def get_week_avg(end_date):
            start_date = end_date - timedelta(days=6)
            cursor.execute("""
                SELECT COUNT(CASE WHEN a.status='present' THEN 1 END) as p,
                       COUNT(DISTINCT a.date, a.class_id) as s
                FROM attendance a
                JOIN classes c ON a.class_id = c.id
                WHERE c.subject_id = %s AND a.date BETWEEN %s AND %s
            """, (subject_id, start_date, end_date))
            r = cursor.fetchone()
            sessions_count = r['s'] or 0
            possible = total_enrolled * sessions_count
            if possible == 0:
                return 0.0
            return (r['p'] / possible * 100)

        current_week_avg = get_week_avg(target_date_obj)
        previous_week_avg = get_week_avg(target_date_obj - timedelta(days=7))

        if previous_week_avg > 0:
            change_val = round(((current_week_avg - previous_week_avg) / previous_week_avg) * 100, 1)
        else:
            change_val = 0.0
        change_rate = f"{'+' if change_val >= 0 else ''}{change_val}%"

        # Trends
        cursor.execute("""
            SELECT MIN(a.date) as first_date
            FROM attendance a
            JOIN classes c ON a.class_id = c.id
            WHERE c.subject_id = %s
        """, (subject_id,))
        row = cursor.fetchone()

        start_date = row['first_date'] if row and row['first_date'] else selected_date_str
        start_date_obj = (
            datetime.strptime(start_date, '%Y-%m-%d').date()
            if isinstance(start_date, str) else start_date
        )
        target_date = datetime.strptime(selected_date_str, '%Y-%m-%d').date()
        day_count = max((target_date - start_date_obj).days + 1, 7)

        trends = []
        for i in range(day_count - 1, -1, -1):
            curr_d = target_date - timedelta(days=i)
            curr_d_str = curr_d.strftime('%Y-%m-%d')

            cursor.execute("""
                SELECT COUNT(CASE WHEN a.status='present' THEN 1 END) as present_count,
                       COUNT(DISTINCT a.class_id) as session_count
                FROM attendance a
                JOIN classes c ON a.class_id = c.id
                WHERE c.subject_id = %s AND a.date = %s
            """, (subject_id, curr_d_str))
            res = cursor.fetchone()
            p_count = res['present_count'] or 0
            s_count = res['session_count'] or 0
            rate = round((p_count / (total_enrolled * s_count)) * 100, 1) if s_count > 0 and total_enrolled > 0 else 0

            cursor.execute("""
                SELECT a.class_id,
                       COUNT(CASE WHEN a.status='present' THEN 1 END) as present
                FROM attendance a
                JOIN classes c ON a.class_id = c.id
                WHERE c.subject_id = %s AND a.date = %s
                GROUP BY a.class_id
                ORDER BY a.class_id
            """, (subject_id, curr_d_str))
            session_rows = cursor.fetchall()
            sessions = [{"session_no": idx, "present": s['present'], "total": total_enrolled}
                        for idx, s in enumerate(session_rows, start=1)]

            trends.append({
                "day_name": curr_d.strftime('%a'),
                "date": curr_d_str,
                "rate": rate,
                "present_count": p_count,
                "total_students": total_enrolled,
                "sessions": sessions,
            })

        # Student Details — JOIN courses to get the short_name as 'course'
        if class_id:
            cursor.execute("""
                SELECT 
                    s.name,
                    s.student_card_id AS student_formal_id,
                    co.short_name AS course,
                    COALESCE(a.status, 'absent') AS status,
                    IFNULL(DATE_FORMAT(a.created_at, '%h:%i %p'), '-') AS time_in
                FROM students s
                JOIN enrollments e ON s.id = e.student_id
                LEFT JOIN courses co ON s.course_id = co.id
                LEFT JOIN attendance a ON s.id = a.student_id
                    AND a.class_id = %s
                    AND a.date = %s
                WHERE e.subject_id = %s
            """, (class_id, selected_date_str, subject_id))
        else:
            cursor.execute("""
                SELECT 
                    s.name,
                    s.student_card_id AS student_formal_id,
                    co.short_name AS course,
                    '-' AS status,
                    '-' AS time_in
                FROM students s
                JOIN enrollments e ON s.id = e.student_id
                LEFT JOIN courses co ON s.course_id = co.id
                WHERE e.subject_id = %s
            """, (subject_id,))

        student_details = cursor.fetchall()

        return jsonify({
            "total_present": present_today,
            "avg_rate": avg_rate_val,
            "daily_rate": daily_rate,
            "change_rate": change_rate,
            "trends": trends,
            "student_details": student_details,
        })
    finally:
        cursor.close()
        db.close()