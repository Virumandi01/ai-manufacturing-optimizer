import os
from flask import Flask, jsonify, request
import psycopg2
from dotenv import load_dotenv
from ortools.sat.python import cp_model
from datetime import datetime, timedelta, timezone
import json 

# Load environment variables from .env file
load_dotenv()

app = Flask(__name__)

# --- Database Connection Function ---
def get_db_connection():
    """Establishes a connection to the PostgreSQL database."""
    try:
        conn = psycopg2.connect(
            database=os.getenv('DB_NAME'),
            user=os.getenv('DB_USER'),
            password=os.getenv('DB_PASSWORD'),
            host=os.getenv('DB_HOST'),
            port=os.getenv('DB_PORT')
        )
        return conn
    except Exception as e:
        print(f"Database connection failed: {e}")
        return None
# ai_scheduler_backend/app.py (REPLACEMENT for calculate_sequential_schedule)

def calculate_sequential_schedule(conn, machine_id, duration_hours):
    """
    Calculates the Start and End time for a new task sequentially on a machine.
    """
    cur = conn.cursor()
    
    # Find the latest scheduled end time for this machine
    cur.execute(
        """
        SELECT MAX(end_time) 
        FROM tasks 
        WHERE required_machine_id = %s;
        """,
        (machine_id,)
    )
    # FIX: Safely retrieve the result
    latest_end_time_result = cur.fetchone()
    
    # Set the new task's start time
    if latest_end_time_result and latest_end_time_result[0] is not None:
        # If a task exists, start immediately after it ends
        start_time = latest_end_time_result[0]
    else:
        # If no task exists, start now (ensure it is timezone-aware)
        start_time = datetime.now(timezone.utc)
        
    # Ensure start_time is rounded for clean calculation
    start_time = start_time.replace(second=0, microsecond=0)
        
    # Calculate the end time
    duration_delta = timedelta(hours=duration_hours)
    end_time = start_time + duration_delta
    
    cur.close()
    return start_time, end_time
# --- Helper Function for Optimizer ---
def fetch_scheduling_data(conn):
    """Fetches machines, tasks, and precedences required for the solver."""
    cur = conn.cursor()
    
    # Fetch all machines
    cur.execute("SELECT machine_id, capacity FROM machines ORDER BY machine_id;")
    machines = {row[0]: {'capacity': row[1]} for row in cur.fetchall()}
    
    # Fetch all tasks (unscheduled or pending)
    cur.execute("""
        SELECT 
            t.task_id, t.job_id, t.duration_hours, t.required_machine_id 
        FROM tasks t 
        WHERE t.status != 'Completed' AND t.status != 'Scheduled' 
        ORDER BY t.task_id;
    """)
    tasks = {row[0]: {'job_id': row[1], 'duration': row[2], 'machine_id': row[3]} 
             for row in cur.fetchall()}

    # Fetch precedences (A must finish before B starts)
    cur.execute("SELECT predecessor_task_id, successor_task_id FROM precedences;")
    precedences = cur.fetchall()
    
    cur.close()
    return machines, tasks, precedences

# --- API Endpoint 1: Get the Current Schedule/Tasks ---
@app.route('/api/schedule', methods=['GET'])
def get_schedule():
    """Fetches the current list of tasks and their status from the DB."""
    conn = get_db_connection()
    if conn is None:
        return jsonify({"error": "Could not connect to database. Check DB credentials."}), 500

    cur = conn.cursor()

    # Query to fetch all task details along with the required machine name
    query = """
    SELECT
        t.task_id, t.job_id, t.name AS task_name, t.duration_hours,
        m.name AS machine_name, t.status, t.start_time, t.end_time
    FROM tasks t
    JOIN machines m ON t.required_machine_id = m.machine_id
    ORDER BY t.task_id;
    """

    cur.execute(query)
    tasks_data = cur.fetchall()

    # Map the data to column names for clean JSON output
    columns = [desc[0] for desc in cur.description]
    schedule = [dict(zip(columns, row)) for row in tasks_data]

    cur.close()
    conn.close()

    return jsonify(schedule)

@app.route('/machines', methods=['GET'])
def get_machines():
    """Fetches a list of all machines for the dropdown and management screen."""
    conn = get_db_connection()
    if conn is None:
        return jsonify({"error": "Could not connect to database."}), 500

    cur = conn.cursor()
    cur.execute("SELECT machine_id, name, capacity FROM machines ORDER BY machine_id;")
    
    machines_data = cur.fetchall()
    columns = [desc[0] for desc in cur.description]
    machines_list = [dict(zip(columns, row)) for row in machines_data]

    cur.close()
    conn.close()

    return jsonify(machines_list)


# --- API Endpoint 2: CREATE NEW TASK ---
@app.route('/tasks', methods=['POST'])
def add_task():
    """Receives new task data and inserts it into the tasks table with a temporary sequential schedule."""
    conn = None 
    try:
        data = request.get_json()
        
        name = data.get('name')
        duration_hours = data.get('duration_hours')
        machine_name = data.get('machine_name')
        
        if not name or not duration_hours or not machine_name:
            return jsonify({"message": "Missing required fields (name, duration_hours, machine_name)"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        # FIX 1: Determine the next available job ID
        cur.execute("SELECT COALESCE(MAX(job_id), 0) + 1 FROM tasks;")
        new_job_id = cur.fetchone()[0]
        
        # Step 1: Get the machine_id from the machine_name
        cur.execute("SELECT machine_id FROM machines WHERE name = %s", (machine_name,))
        machine_result = cur.fetchone()

        if not machine_result:
            cur.close()
            conn.close()
            return jsonify({"message": f"Machine not found: {machine_name}"}), 404
        
        machine_id = machine_result[0]

        # --- STEP 2: CALCULATE SEQUENTIAL SCHEDULE ---
        start_time, end_time = calculate_sequential_schedule(conn, machine_id, duration_hours)

        # Step 3: Insert the new task using the new_job_id
        cur.execute(
            """
            INSERT INTO tasks 
            (job_id, name, duration_hours, required_machine_id, status, start_time, end_time) 
            VALUES (%s, %s, %s, %s, 'Pending', %s, %s)
            RETURNING task_id;
            """,
            # IMPORTANT: Use the calculated new_job_id
            (new_job_id, name, duration_hours, machine_id, start_time, end_time) 
        )
        task_id = cur.fetchone()[0]
        
        conn.commit()
        cur.close()
        
        return jsonify({"message": f"Task '{name}' added with ID {task_id}. Run optimizer for true schedule."}), 201

    except Exception as e:
        print(f"Error adding task: {e}")
        if conn:
            conn.rollback()
        return jsonify({"message": f"An internal error occurred: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()

# --- API Endpoint 3: ADD PRECEDENCE RULE ---
@app.route('/precedences', methods=['POST'])
def add_precedence():
    """Adds a new precedence rule (Task A must finish before Task B starts)."""
    conn = None
    try:
        data = request.get_json()
        predecessor_id = data.get('predecessor_id')
        successor_id = data.get('successor_id')
        
        if not predecessor_id or not successor_id:
            return jsonify({"message": "Missing required fields (predecessor_id, successor_id)"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            """
            INSERT INTO precedences 
            (predecessor_task_id, successor_task_id) 
            VALUES (%s, %s);
            """,
            predecessor_id = data.get('predecessor_id')
        )
        
        conn.commit()
        cur.close()
        conn.close()

        return jsonify({"message": f"Precedence rule added: Task {successor_id} follows Task {predecessor_id}."}), 201

    except Exception as e:
        print(f"Error adding precedence: {e}")
        return jsonify({"message": f"An internal error occurred: {str(e)}"}), 500


# --- API Endpoint 4: UPDATE TASK STATUS ---
@app.route('/tasks/<int:task_id>/status', methods=['PATCH'])
def update_task_status(task_id):
    """Updates the status of a specific task."""
    conn = None
    try:
        data = request.get_json()
        new_status = data.get('status')
        
        if not new_status:
            return jsonify({"message": "Missing required field: status"}), 400

        # Validate status to prevent injection and ensure a valid state
        valid_statuses = ['In Progress', 'Completed', 'Canceled', 'Pending', 'Scheduled']
        if new_status not in valid_statuses:
            return jsonify({"message": f"Invalid status: {new_status}. Must be one of {valid_statuses}"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        # Update the task status
        cur.execute(
            """
            UPDATE tasks 
            SET status = %s
            WHERE task_id = %s;
            """,
            (new_status, task_id)
        )
        
        if cur.rowcount == 0:
            return jsonify({"message": f"Task with ID {task_id} not found."}), 404

        conn.commit()
        cur.close()

        # Instruct the manager to run optimization to re-schedule based on the new status
        return jsonify({"message": f"Task {task_id} status updated to '{new_status}'. RUN OPTIMIZER NOW."}), 200

    except Exception as e:
        print(f"Error updating task status: {e}")
        return jsonify({"error": f"An internal error occurred: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()

# --- API Endpoint 5: ADD NEW MACHINE ---
@app.route('/machines', methods=['POST'])
def add_machine():
    """Receives new machine data and inserts it into the machines table."""
    conn = None
    try:
        data = request.get_json()
        name = data.get('name')
        # Capacity defaults to 1 if not provided
        capacity = data.get('capacity', 1) 
        
        if not name:
            return jsonify({"message": "Missing required field: name"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            """
            INSERT INTO machines (name, capacity) 
            VALUES (%s, %s)
            RETURNING machine_id;
            """,
            (name, capacity)
        )
        machine_id = cur.fetchone()[0]
        
        conn.commit()
        cur.close()
        conn.close()

        return jsonify({"message": f"Machine '{name}' added with ID {machine_id}."}), 201

    except Exception as e:
        print(f"Error adding machine: {e}")
        return jsonify({"message": f"An internal error occurred: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()

# --- API Endpoint 6: AI Optimization ---
# ai_scheduler_backend/app.py

# ... (rest of the code) ...

# --- API Endpoint 6: AI Optimization ---
# --- API Endpoint 6: AI Optimization ---
@app.route('/api/optimize', methods=['POST'])
def run_optimization():
    conn = get_db_connection()
    if conn is None:
        return jsonify({"error": "Could not connect to database"}), 500

    try:
        # FIX: Use silent=True and default to empty dict to prevent crash if body is missing/malformed
        data = request.get_json(silent=True) or {} 
        start_time_str = data.get('start_time')
        
        # --- Parse the User-Defined Start Time ---
        if start_time_str:
            try:
                # FIX: Use the reliable parsing method
                clean_time_str = start_time_str.split('.')[0] 
                schedule_start_time = datetime.strptime(clean_time_str, '%Y-%m-%dT%H:%M:%S').replace(tzinfo=timezone.utc)
            except ValueError:
                return jsonify({"message": "Invalid start time format. Please select a valid time."}), 400
        else:
            # Fallback to current time 
            schedule_start_time = datetime.now(timezone.utc).replace(second=0, microsecond=0)
        
        schedule_start_time = schedule_start_time.replace(second=0, microsecond=0) # Round to minute


        machines, tasks, precedences = fetch_scheduling_data(conn)
        
        # Check if there are tasks to schedule (prevents crash if list is empty)
        if not tasks:
             return jsonify({"message": "Optimization successful. No pending tasks found to schedule."}), 200


        # --- 1. Define the Scheduling Horizon and Model ---
        model = cp_model.CpModel()
        horizon = 100000 
        
        # --- 2. Create Variables for Each Task ---
        task_vars = {}
        for task_id, data in tasks.items():
            # Ensure duration is treated as a float/double before conversion
            duration_minutes = int(float(data['duration']) * 60)
            
            # Start, End, and Interval variables for each task
            start_var = model.NewIntVar(0, horizon, f'start_{task_id}')
            end_var = model.NewIntVar(0, horizon, f'end_{task_id}')
            interval_var = model.NewIntervalVar(start_var, duration_minutes, end_var, f'interval_{task_id}')
            
            task_vars[task_id] = {
                'start': start_var,
                'end': end_var,
                'interval': interval_var,
                'machine_id': data['machine_id'],
                'duration_minutes': duration_minutes
            }

        # --- 3. Enforce Precedence Constraints (Supply Chain Constraints) ---
        for predecessor_id, successor_id in precedences:
            if predecessor_id in task_vars and successor_id in task_vars:
                model.Add(task_vars[successor_id]['start'] >= task_vars[predecessor_id]['end'])
                
        # --- 4. Enforce Machine Capacity Constraints (Equipment Capacity) ---
        machine_intervals = {m_id: [] for m_id in machines.keys()}
        for t_vars in task_vars.values():
            m_id = t_vars['machine_id']
            if m_id in machine_intervals:
                machine_intervals[m_id].append(t_vars['interval'])

        for m_id, intervals in machine_intervals.items():
            if machines[m_id]['capacity'] == 1:
                model.AddNoOverlap(intervals)

        # --- 5. Objective Function (Efficiency Improvements) ---
        all_ends = [t_vars['end'] for t_vars in task_vars.values()]
        if all_ends:
            max_end_time = model.NewIntVar(0, horizon, 'max_end_time')
            model.AddMaxEquality(max_end_time, all_ends)
            model.Minimize(max_end_time)
            
        # --- 6. Solve and Process Solution ---
        solver = cp_model.CpSolver()
        status = solver.Solve(model)

        if status == cp_model.OPTIMAL or status == cp_model.FEASIBLE:
            # We found a schedule! Update the database.
            
            cur = conn.cursor()
            for task_id, t_vars in task_vars.items():
                start_minutes_offset = solver.Value(t_vars['start'])
                end_minutes_offset = solver.Value(t_vars['end'])
                
                # CRITICAL: Use the user-defined schedule_start_time
                actual_start_time = schedule_start_time + timedelta(minutes=start_minutes_offset)
                actual_end_time = schedule_start_time + timedelta(minutes=end_minutes_offset)
                
                cur.execute("""
                    UPDATE tasks 
                    SET start_time = %s, end_time = %s, status = 'Scheduled' 
                    WHERE task_id = %s;
                """, (actual_start_time, actual_end_time, task_id))
            
            conn.commit()
            cur.close()
            
            return jsonify({
                "message": "Optimization successful. New schedule generated and saved.",
                "makespan_minutes": solver.ObjectiveValue(),
                "status": "OPTIMAL"
            }), 200
        else:
            return jsonify({
                "message": "Optimization failed. No feasible schedule found. Check your tasks and machines.",
                "status": "INFEASIBLE"
            }), 400

    except Exception as e:
        print(f"Error during optimization: {e}")
        conn.rollback()
        return jsonify({"error": f"An internal error occurred: {e}"}), 500
    finally:
        if conn:
            conn.close()


# --- API Endpoint 7: DELETE TASK ---
@app.route('/tasks/<int:task_id>', methods=['DELETE'])
def delete_task(task_id):
    """Deletes a task and any associated precedence rules."""
    conn = None
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        # Step 1: Delete associated precedence rules first (to satisfy foreign keys)
        cur.execute(
            """
            DELETE FROM precedences 
            WHERE predecessor_task_id = %s OR successor_task_id = %s;
            """,
            (task_id, task_id)
        )
        
        # Step 2: Delete the task itself
        cur.execute(
            """
            DELETE FROM tasks 
            WHERE task_id = %s;
            """,
            (task_id,)
        )
        
        if cur.rowcount == 0:
            return jsonify({"message": f"Task with ID {task_id} not found."}), 404

        conn.commit()
        cur.close()
        
        return jsonify({"message": f"Task {task_id} successfully deleted. Run optimizer to re-schedule remaining tasks."}), 200

    except Exception as e:
        print(f"Error deleting task: {e}")
        conn.rollback()
        return jsonify({"error": f"An internal error occurred: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()

# --- API Endpoint 8: EDIT/UPDATE TASK DETAILS ---
@app.route('/tasks/<int:task_id>', methods=['PATCH'])
def edit_task_details(task_id):
    """
    Updates the name, duration, or machine_name of a task.
    Note: Optimization must be rerun after this update.
    """
    conn = None
    try:
        data = request.get_json()
        
        # Check if we have any fields to update
        if not any(key in data for key in ['name', 'duration_hours', 'machine_name']):
            return jsonify({"message": "No valid fields provided for update (name, duration_hours, machine_name)."}), 400

        conn = get_db_connection()
        cur = conn.cursor()
        
        updates = []
        params = []
        
        # 1. Update Task Name
        if 'name' in data:
            updates.append("name = %s")
            params.append(data['name'])
            
        # 2. Update Duration
        if 'duration_hours' in data:
            updates.append("duration_hours = %s")
            params.append(data['duration_hours'])

        # 3. Update Required Machine
        if 'machine_name' in data:
            machine_name = data['machine_name']
            # Sub-step: Get machine_id from machine_name
            cur.execute("SELECT machine_id FROM machines WHERE name = %s", (machine_name,))
            machine_result = cur.fetchone()
            
            if not machine_result:
                cur.close()
                conn.close()
                return jsonify({"message": f"Machine not found: {machine_name}"}), 404
            
            machine_id = machine_result[0]
            updates.append("required_machine_id = %s")
            params.append(machine_id)

        # Append the task_id to the parameters list for the WHERE clause
        params.append(task_id)
        
        # Construct the final SQL command
        sql_query = f"""
        UPDATE tasks 
        SET {', '.join(updates)}, 
            status = 'Pending', 
            start_time = NULL, 
            end_time = NULL 
        WHERE task_id = %s;
        """

        cur.execute(sql_query, tuple(params))
        
        if cur.rowcount == 0:
            return jsonify({"message": f"Task with ID {task_id} not found."}), 404

        conn.commit()
        cur.close()
        
        return jsonify({"message": f"Task {task_id} updated successfully. Status reset to PENDING. RUN OPTIMIZER NOW."}), 200

    except Exception as e:
        print(f"Error editing task details: {e}")
        conn.rollback()
        return jsonify({"error": f"An internal error occurred: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()

# --- API Endpoint 10: Log Production Results ---
@app.route('/api/production_log', methods=['POST'])
def log_production():
    data = request.get_json()
    task_id = data.get('task_id')
    resource_used = data.get('resource_used')
    product_count = data.get('product_count')

    # Basic input validation
    if not all([task_id, resource_used, product_count]):
        return jsonify({"error": "Missing task_id, resource_used, or product_count"}), 400
    
    # Validation
    try:
        task_id = int(task_id) # Ensure task_id is integer
        product_count = int(product_count)
        if product_count < 0:
            raise ValueError("Product count cannot be negative")
    except ValueError:
        return jsonify({"error": "Product count or task_id must be a valid integer"}), 400

    conn = get_db_connection()
    if conn is None:
        return jsonify({"error": "Could not connect to database"}), 500

    try:
        cur = conn.cursor()
        
        # Insert the production log into the new table
        cur.execute(
            """
            INSERT INTO production_logs (task_id, resource_used, product_count)
            VALUES (%s, %s, %s)
            """,
            (task_id, resource_used, product_count)
        )
        conn.commit()
        cur.close()

        return jsonify({
            "message": f"Production log saved successfully for Task ID {task_id}.",
        }), 201 # 201 Created

    except Exception as e:
        conn.rollback()
        print(f"Error logging production: {e}")
        return jsonify({"error": f"Internal server error: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()

# --- API Endpoint 12: Get All Tasks (for dropdown) ---
@app.route('/api/tasks', methods=['GET'])
def get_all_tasks():
    conn = get_db_connection()
    if conn is None:
        return jsonify({"error": "Could not connect to database"}), 500

    try:
        cur = conn.cursor()
        # Only fetch the ID and Name for the dropdown
        cur.execute("SELECT task_id, name FROM tasks ORDER BY task_id;")
        tasks = cur.fetchall()
        cur.close()

        tasks_list = []
        for task in tasks:
            tasks_list.append({
                'task_id': task[0],
                'name': task[1]
            })

        return jsonify(tasks_list), 200

    except Exception as e:
        print(f"Error fetching tasks for dropdown: {e}")
        return jsonify({"error": f"Internal server error: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()

# --- API Endpoint 9: DELETE MACHINE ---
@app.route('/api/machines/<int:machine_id>', methods=['DELETE'])
def delete_machine(machine_id):
    """Deletes a machine if it is not currently required by any task."""
    conn = None
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        # Step 1: Check if the machine is referenced by any existing task
        cur.execute(
            """
            SELECT COUNT(*) FROM tasks 
            WHERE required_machine_id = %s;
            """,
            (machine_id,)
        )
        task_count = cur.fetchone()[0]

        if task_count > 0:
            cur.close()
            conn.close()
            return jsonify({
                "message": f"Cannot delete machine ID {machine_id}. It is currently required by {task_count} task(s)."
            }), 409 # Conflict

        # Step 2: Delete the machine
        cur.execute(
            """
            DELETE FROM machines 
            WHERE machine_id = %s;
            """,
            (machine_id,)
        )
        
        if cur.rowcount == 0:
            return jsonify({"message": f"Machine with ID {machine_id} not found."}), 404

        conn.commit()
        cur.close()
        
        return jsonify({"message": f"Machine ID {machine_id} successfully deleted."}), 200

    except Exception as e:
        print(f"Error deleting machine: {e}")
        conn.rollback()
        return jsonify({"error": f"An internal error occurred: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()

# --- Run the Flask Application ---
if __name__ == '__main__':
    # Flask will run on http://127.0.0.1:5000/
    app.run(debug=True, host='0.0.0.0')