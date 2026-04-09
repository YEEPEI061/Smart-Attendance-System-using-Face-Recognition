import os
import mysql.connector
from dotenv import load_dotenv

load_dotenv()

DB_HOST = os.environ.get("DB_HOST", "127.0.0.1")
DB_PORT = int(os.environ.get("DB_PORT", 3306))
DB_DATABASE = os.environ.get("DB_DATABASE", "attendance")
DB_USERNAME = os.environ.get("DB_USERNAME", "root")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")

# Connect
db = mysql.connector.connect(
    host=DB_HOST,
    port=DB_PORT,
    user=DB_USERNAME,
    password=DB_PASSWORD,
    database=DB_DATABASE
)
cursor = db.cursor()

# ----------------------
# CREATE COURSES TABLE
# ----------------------
cursor.execute("""
CREATE TABLE IF NOT EXISTS courses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    short_name VARCHAR(20) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
""")

# ----------------------
# INSERT COURSES
# ----------------------
courses = [
    ("Diploma of Accountancy", "DOAC"),
    ("Diploma in Business Studies", "DIBS"),
    ("Diploma in Computer Science", "DICS"),
    ("Diploma in Logistics Management", "DILM"),
    ("Diploma in E-Business Technology", "DIEB"),
    ("Diploma in Electrical and Electronics Engineering Technology", "DIEE"),

    ("BSc (Hons) Business Management (UK) 3+0", "BSBM"),
    ("BSc (Hons) Maritime Business (Logistics) (UK) 3+0", "BMBL"),
    ("BA (Hons) Accounting and Finance (Accounting) (UK) 3+0", "BACF"),
    ("BSc (Hons) Computer Science (Cyber Security) (UK) 3+0", "BSCS"),
    ("BSc (Hons) Computer Science (Software Engineering) (UK) 3+0", "BSSE"),
]

for full_name, short_name in courses:
    cursor.execute("""
        INSERT IGNORE INTO courses (full_name, short_name)
        VALUES (%s, %s)
    """, (full_name, short_name))

db.commit()
cursor.close()
db.close()

print("Courses table created and data inserted successfully!")