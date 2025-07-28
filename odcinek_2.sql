-- =================================================================
-- TWORZENIE FUNKCJI I WYZWALACZY (TRIGGERS) DO AUDYTU
-- =================================================================

-- Przełącza rolę na 'admin_user' w celu testowania uprawnień.
SET ROLE admin_user;

-- Tworzy lub zastępuje funkcję 'log_event', która będzie wywoływana przez wyzwalacze.
CREATE OR REPLACE FUNCTION log_event()
    RETURNS TRIGGER AS $$
DECLARE role_user_id BIGINT; -- Deklaruje zmienną do przechowywania ID użytkownika.
BEGIN
    -- Pobiera ID użytkownika na podstawie nazwy bieżącej roli ('current_user').
    SELECT user_id INTO role_user_id FROM app_security.app_roles WHERE app_role = current_user;
    -- Wstawia nowy rekord do tabeli logów.
    INSERT INTO auditing.logs (user_id, event, date, details)
    VALUES (role_user_id, TG_TABLE_NAME || TG_ARGV[0], NOW(), row_to_json(NEW)); -- 'TG_TABLE_NAME' to nazwa tabeli, 'TG_ARGV[0]' to argument przekazany z wyzwalacza, 'NEW' to nowy/zmieniony wiersz.
    RETURN NEW; -- Zwraca nowy wiersz, co jest wymagane dla wyzwalaczy AFTER.
END;
$$ LANGUAGE plpgsql;

-- Tworzy wyzwalacz 'log_insert_emp', który uruchamia funkcję 'log_event' po każdej operacji INSERT na tabeli 'employees'.
CREATE OR REPLACE TRIGGER log_insert_emp
    AFTER INSERT ON public.employees
    FOR EACH ROW
EXECUTE FUNCTION log_event('INSERT'); -- Przekazuje 'INSERT' jako argument do funkcji.

-- Testuje wyzwalacz przez wstawienie nowego pracownika. To powinno utworzyć wpis w tabeli 'auditing.logs'.
INSERT INTO public.employees (full_name, email, salary) VALUES ('Jan Nowak', 'jnowak@test.example', 10000);

-- Tworzy wyzwalacz 'log_update_emp' dla operacji UPDATE na tabeli 'employees'.
CREATE OR REPLACE TRIGGER log_update_emp
    AFTER UPDATE ON public.employees
    FOR EACH ROW
EXECUTE FUNCTION log_event('UPDATE'); -- Przekazuje 'UPDATE' jako argument.

-- Testuje wyzwalacz przez aktualizację danych pracownika. To również powinno utworzyć log.
UPDATE public.employees SET full_name = 'Jacek Nowak' WHERE email = 'jnowak@test.example';

-- =================================================================
-- ZAAWANSOWANE ZARZĄDZANIE ROLAMI I FUNKCJA DO DODAWANIA PRACOWNIKÓW
-- =================================================================

-- Przełącza się z powrotem na superużytkownika 'postgres', aby móc modyfikować uprawnienia innych ról.
SET ROLE postgres;

-- Nadaje roli 'admin_user' uprawnienie do tworzenia innych ról (CREATEROLE).
ALTER ROLE admin_user CREATEROLE;

-- Wraca do roli 'admin_user', która ma teraz rozszerzone uprawnienia.
SET ROLE admin_user;

-- Tworzy zaawansowaną funkcję 'add_employee' do dodawania nowego pracownika wraz z jego kontem w bazie danych.
CREATE OR REPLACE FUNCTION add_employee(
    emp_full_name TEXT,
    emp_email TEXT,
    emp_role_id BIGINT,
    emp_salary DECIMAL,
    emp_department_id BIGINT,
    login_role_name TEXT,
    login_role_group TEXT,
    login_password TEXT)
    RETURNS VOID AS $$
DECLARE new_emp_id BIGINT; new_user_id BIGINT; -- Deklaruje zmienne lokalne.
BEGIN
    -- Dynamicznie tworzy nową rolę z hasłem dla nowego pracownika.
    EXECUTE format('CREATE ROLE %I WITH LOGIN PASSWORD %L', login_role_name, login_password);
    -- Dynamicznie przypisuje nowo utworzoną rolę do podanej grupy.
    EXECUTE format('GRANT %I TO %I', login_role_group, login_role_name);
    -- Wstawia dane pracownika do tabeli 'employees' i pobiera jego ID.
    INSERT INTO public.employees (full_name, email, role_id, salary, department_id) VALUES (emp_full_name, emp_email,emp_role_id, emp_salary, emp_department_id)
    RETURNING employee_id INTO new_emp_id;
    -- Tworzy powiązany rekord w tabeli 'users' i pobiera jego ID.
    INSERT INTO app_security.users (employee_id, created_at, updated_at) VALUES (new_emp_id, NOW(), NOW())
    RETURNING user_id INTO new_user_id;
    -- Przypisuje rolę aplikacyjną do nowego użytkownika.
    INSERT INTO app_security.app_roles (user_id, app_role) VALUES (new_user_id, login_role_name);
END;
    -- 'LANGUAGE plpgsql' określa język funkcji.
-- 'SECURITY DEFINER' sprawia, że funkcja wykonuje się z uprawnieniami jej twórcy (tutaj 'admin_user'), a nie użytkownika, który ją wywołuje.
$$ LANGUAGE  plpgsql SECURITY DEFINER;

-- Tworzy nową grupę ról 'hr_group' dla działu HR.
CREATE ROLE hr_group;

-- Przełącza się na superużytkownika, aby zarządzać uprawnieniami między grupami.
SET ROLE postgres;

-- Nadaje grupie 'hr_group' uprawnienia do roli 'admin_user' z opcją 'ADMIN OPTION',
-- co pozwala członkom 'hr_group' na nadawanie roli 'admin_user' innym.
GRANT hr_group TO admin_user WITH ADMIN OPTION;

-- Wraca do roli 'admin_user'.
SET ROLE admin_user;

-- Wywołuje funkcję 'add_employee' aby dodać nowego pracownika, jego konto i przypisać go do grupy 'hr_group'.
SELECT add_employee('Lila Jagielska', 'ljag@test.example', null, 20000,null, 'ljag','hr_group', 'haselko123');