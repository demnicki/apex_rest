/* Nadanie uprawnieñ do pakietu systemowego ENCRYPT. */
GRANT EXECUTE ON sys.dbms_crypto TO wksp_kurs;

/* Stworzenie klastra do tabel "U¿ytkownicy" i "Raport programisty". */
CREATE CLUSTER moj_klaster (id NUMBER(10));

CREATE INDEX i_klastra ON CLUSTER moj_klaster;

/* Tworzenie sekwencji dla tabeli "U¿ytkownicy". */
CREATE SEQUENCE s_uzytkownicy
MINVALUE   1000
MAXVALUE   9999
START WITH 1000;

/* Tworzenie sekwencji dla tabeli "Logi". */
CREATE SEQUENCE s_logi_uzytk
MINVALUE   1
MAXVALUE   10000
START WITH 1;

/* Stworzenie sekwencji dla tabeli "Raport programisty". */
CREATE SEQUENCE s_raport
MINVALUE   1
MAXVALUE   1000
START WITH 1;

/* Stworzenie tabeli "Ksi¹¿ki" w ramach klastra "Mój klaster". */
CREATE TABLE uzytkownicy(
id              NUMBER DEFAULT ON NULL s_uzytkownicy.NEXTVAL NOT NULL,
login_mail      VARCHAR2(250 CHAR) NOT NULL,
rola            CHAR(1 CHAR) DEFAULT 'k' NOT NULL,
i_prob          NUMBER(1) DEFAULT 3 NOT NULL,
pseudonim       VARCHAR2(250 CHAR),
plec            CHAR(1 CHAR) DEFAULT 'm' NOT NULL,
data_utworzenia TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
CONSTRAINT c_plec CHECK (lower(plec) in ('m','k')),
CONSTRAINT c_rola CHECK (lower(rola) in ('k','s', 'p')),
CONSTRAINT klucz1 PRIMARY KEY (id),
CONSTRAINT unik1 UNIQUE (login_mail)
)CLUSTER moj_klaster(id);

/* Tworzenie tabeli "Logi" z kluczem obcym z tabeli "U¿ytkownicy". */
CREATE TABLE logi_uzytk(
id             NUMBER DEFAULT ON NULL s_logi_uzytk.NEXTVAL NOT NULL,
id_uzytkownika NUMBER NOT NULL,
ip             VARCHAR2(16 CHAR),
agent_klienta  VARCHAR2(500 CHAR),
status         CHAR(1 CHAR) DEFAULT 'n' NOT NULL,
data_logu      TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
CONSTRAINT klucz_2 PRIMARY KEY (id),
CONSTRAINT c_status CHECK (lower(status) in ('u','n')),
CONSTRAINT k_uzytk2 FOREIGN KEY (id_uzytkownika) REFERENCES uzytkownicy(id)
)CLUSTER moj_klaster(id);

/* Stworzenie tabeli "Raport programisty". */
CREATE TABLE raport_programisty(
id              NUMBER DEFAULT ON NULL s_raport.NEXTVAL NOT NULL,
id_uzytkownika  NUMBER NOT NULL,
id_logu         NUMBER NOT NULL,
komentarz       VARCHAR2(1000 CHAR),
CONSTRAINT klucz_3 PRIMARY KEY (id),
CONSTRAINT k_uzytk3 FOREIGN KEY (id_uzytkownika) REFERENCES uzytkownicy(id),
CONSTRAINT k_uzytk4 FOREIGN KEY (id_logu) REFERENCES logi_uzytk(id)
)CLUSTER moj_klaster(id_uzytkownika);

/* Stworzenie procedury "Raportuj". */
CREATE OR REPLACE PROCEDURE raportuj(
a_komentarz IN raport_programisty.komentarz%TYPE
)
IS
czy_jest     NUMBER;
z_id         uzytkownicy.id%TYPE;
z_id_logi    logi_uzytk.id%TYPE;
z_ip         logi_uzytk.ip%TYPE;
z_agent      logi_uzytk.agent_klienta%TYPE;
z_prog       uzytkownicy.login_mail%TYPE;
BEGIN
SAVEPOINT aa;
z_prog := lower(apex_application.g_user);
SELECT count(login_mail), cast(owa_util.get_cgi_env('REMOTE_ADDR') AS VARCHAR2(16 CHAR)), owa_util.get_cgi_env('HTTP_USER_AGENT')
INTO czy_jest, z_ip, z_agent FROM uzytkownicy WHERE login_mail = z_prog;
IF czy_jest != 1 THEN
	INSERT INTO uzytkownicy (login_mail, rola, pseudonim) VALUES (z_prog, 'p', z_prog);
END IF;
SELECT id INTO z_id FROM uzytkownicy WHERE login_mail = z_prog;
INSERT INTO logi_uzytk (id_uzytkownika, ip, agent_klienta, status) VALUES (z_id, z_ip, z_agent, 'u');
SELECT id INTO z_id_logi FROM (SELECT id FROM logi_uzytk WHERE id_uzytkownika = z_id ORDER BY data_logu DESC) WHERE ROWNUM = 1;
INSERT INTO raport_programisty (id_uzytkownika, id_logu, komentarz) VALUES (z_id, z_id_logi, a_komentarz);
COMMIT;
dbms_output.put_line('Dodano raport programisty '||z_prog ||' o adresie IP '||z_ip||' loguj¹cego siê z urz¹dzenia o oznaczeniu '||z_agent||'.');
EXCEPTION
WHEN OTHERS THEN
	ROLLBACK TO aa;
	dbms_output.put_line('Nie uda³o siê. B³¹d bazy danych.');
END raportuj;

BEGIN
raportuj(a_komentarz => 'Witaj piekny Œwiecie..');
END;

/* Nadania uprawnieñ do "Raport programisty". */
GRANT SELECT, INSERT, UPDATE, DELETE ON wksp_kurs.uzytkownicy TO wksp_dyrekcjait;
GRANT SELECT, INSERT, UPDATE, DELETE ON wksp_kurs.uzytkownicy TO kierownik;
GRANT SELECT, INSERT, UPDATE, DELETE ON wksp_kurs.logi_uzytk TO wksp_dyrekcjait;
GRANT SELECT, INSERT, UPDATE, DELETE ON wksp_kurs.logi_uzytk TO kierownik;
GRANT SELECT, INSERT, UPDATE, DELETE ON wksp_kurs.raport_programisty TO wksp_dyrekcjait;
GRANT SELECT, INSERT, UPDATE, DELETE ON wksp_kurs.raport_programisty TO kierownik;

/* Stworzenie widoku dla tebeli "Raport programisty"*/
CREATE VIEW w_logi (id, login_mail, ip,  agent_klienta, data_logu, komentarz)
AS SELECT u.id, u.login_mail, l.ip,  l.agent_klienta, l.data_logu, r.komentarz
FROM wksp_kurs.uzytkownicy u
LEFT JOIN wksp_kurs.logi_uzytk l ON u.id = l.id_uzytkownika
LEFT JOIN wksp_kurs.raport_programisty r ON r.id_logu = l.id;

/* Stworzenie tabeli "Kopia raportów". */
CREATE TABLE k_raportow(
id             NUMBER,
login_mail     VARCHAR2(250 CHAR),
ip             VARCHAR2(16 CHAR),
agent_klienta  VARCHAR2(500 CHAR),
data_logu      TIMESTAMP,
komentarz      VARCHAR2(1000 CHAR)
);

/* Stworzenie procedury "Skopiuj raporty". */
CREATE OR REPLACE PROCEDURE admin.skopiuj_raporty
IS
CURSOR kursor IS SELECT id, login_mail, ip, agent_klienta, data_logu, komentarz FROM wksp_kurs.w_logi;
it NUMBER := 0;
BEGIN
SAVEPOINT aa;
FOR k IN kursor
LOOP
	INSERT INTO wksp_dyrekcjait.k_raportow (id, login_mail, ip, agent_klienta, data_logu, komentarz ) VALUES (k.id, k.login_mail, k.ip, k.agent_klienta, k.data_logu, k.komentarz);
	it := it + 1;
END LOOP;
COMMIT;
dbms_output.put_line('Przekopiowano wiersze z tabeli Raporty programisty, w iloœci: '||it||'.');
EXCEPTION
WHEN OTHERS THEN
	ROLLBACK TO aa;
	dbms_output.put_line('Nie uda³o siê. B³¹d bazy danych.');
END skopiuj_raporty;

BEGIN
skopiuj_raporty;
END;

/* Stworzenie wyzwalacza czasowego na koncie "Admin". */
BEGIN
dbms_scheduler.create_job (
   job_name        => 'auto_k_raporty',
   job_type        => 'STORED_PROCEDURE',
   job_action      => 'skopiuj_raporty',
   start_date      => systimestamp,
   repeat_interval => 'FREQ=DAILY',
   enabled         => TRUE);
END;

/* Przek³adowe s³owniki bazy Oracle. Pokazuje wszystkie definiowane wyzwalacze czasowe JOB. */
SELECT * FROM all_scheduler_jobs WHERE owner = upper('WKSP_KuRS');

/* Pokazuje wszystkie utworzone obiekty. */
SELECT * FROM all_objects WHERE owner = upper('WKSP_KuRS');

/* Pokazuje wszystkie utworzone tabele. */
SELECT * FROM all_tables WHERE owner = upper('WKSP_KuRS');

/* Pokazuje aktywnoœæ programistów platformy APEX. */
SELECT workspace, apex_user, view_date, view_timestamp FROM apex_workspace_activity_log ORDER BY view_timestamp DESC;

/* Pokazuje wszystkich u¿ytkowników platformy APEX. */
SELECT * FROM apex_workspace_apex_users;