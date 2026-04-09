from flask import Flask
from flask_cors import CORS

# Import Blueprints instead of whole files
from login import login_bp
from signup import signup_bp
from dashboard import dashboard_bp
from enroll import enroll_bp
from recognize import recognize_bp
from attendance import attendance_bp
from reports import reports_bp
from setting import setting_bp
from sa_login import sa_login_bp
from sa_dashboard import sa_dashboard_bp
from sa_user import sa_user_bp
from sa_log import sa_log_bp
from sa_changepsw import sa_changepsw_bp
from forgotpsw import forgot_password_bp
from update_student import update_student_bp
from flask import send_from_directory
import os

app = Flask(__name__)
CORS(app, supports_credentials=True)

# Register routes from other files
app.register_blueprint(login_bp)
app.register_blueprint(signup_bp)
app.register_blueprint(dashboard_bp)
app.register_blueprint(enroll_bp)
app.register_blueprint(recognize_bp)
app.register_blueprint(attendance_bp)
app.register_blueprint(reports_bp)
app.register_blueprint(setting_bp)
app.register_blueprint(sa_login_bp)
app.register_blueprint(sa_dashboard_bp)
app.register_blueprint(sa_user_bp)
app.register_blueprint(sa_log_bp)
app.register_blueprint(sa_changepsw_bp)
app.register_blueprint(forgot_password_bp)
app.register_blueprint(update_student_bp)


@app.route("/uploads/<path:filename>")
def uploaded_file(filename):
    uploads_dir = os.path.join(os.getcwd(), "uploads")
    return send_from_directory(uploads_dir, filename)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=True)
