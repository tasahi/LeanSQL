#ifndef LEANSQL_H
#define LEANSQL_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

#define SQLITE_OK           0   /* Successful result */
#define SQLITE_ERROR        1   /* Generic error */
#define SQLITE_INTERNAL     2   /* Internal logic error in SQLite */
#define SQLITE_PERM         3   /* Access permission denied */
#define SQLITE_ABORT        4   /* Callback routine requested an abort */
#define SQLITE_BUSY         5   /* The database file is locked */
#define SQLITE_LOCKED       6   /* A table in the database is locked */
#define SQLITE_NOMEM        7   /* A malloc() failed */
#define SQLITE_READONLY     8   /* Attempt to write a readonly database */
#define SQLITE_INTERRUPT    9   /* Operation terminated by sqlite3_interrupt()*/
#define SQLITE_IOERR       10   /* Some kind of disk I/O error occurred */
#define SQLITE_CORRUPT     11   /* The database disk image is malformed */
#define SQLITE_NOTFOUND    12   /* Unknown opcode in sqlite3_file_control() */
#define SQLITE_FULL        13   /* Insertion failed because database is full */
#define SQLITE_CANTOPEN    14   /* Unable to open the database file */
#define SQLITE_PROTOCOL    15   /* Database lock protocol error */
#define SQLITE_EMPTY       16   /* Internal use only */
#define SQLITE_SCHEMA      17   /* The database schema changed */
#define SQLITE_TOOBIG      18   /* String or BLOB exceeds size limit */
#define SQLITE_CONSTRAINT  19   /* Abort due to constraint violation */
#define SQLITE_MISMATCH    20   /* Data type mismatch */
#define SQLITE_MISUSE      21   /* Library used incorrectly */
#define SQLITE_ROW        100   /* sqlite3_step() has another row ready */
#define SQLITE_DONE       101   /* sqlite3_step() has finished executing */

#define SQLITE_INTEGER  1
#define SQLITE_FLOAT    2
#define SQLITE_TEXT     3
#define SQLITE_BLOB     4
#define SQLITE_NULL     5

typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;

/* Library Info */
const char *sqlite3_libversion(void);
const char *sqlite3_sourceid(void);
int sqlite3_libversion_number(void);

/* Database Connection Management */
int sqlite3_open(const char *filename, sqlite3 **ppDb);
int sqlite3_open_v2(const char *filename, sqlite3 **ppDb, int flags, const char *zVfs);
int sqlite3_close(sqlite3 *pDb);
int sqlite3_close_v2(sqlite3 *pDb);

/* Statement Preparation and Execution */
int sqlite3_prepare_v2(sqlite3 *pDb, const char *zSql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail);
int sqlite3_step(sqlite3_stmt *pStmt);
int sqlite3_reset(sqlite3_stmt *pStmt);
int sqlite3_finalize(sqlite3_stmt *pStmt);

/* Result Columns */
int sqlite3_column_count(sqlite3_stmt *pStmt);
int sqlite3_column_type(sqlite3_stmt *pStmt, int iCol);
const char *sqlite3_column_name(sqlite3_stmt *pStmt, int iCol);
int64_t sqlite3_column_int64(sqlite3_stmt *pStmt, int iCol);
int sqlite3_column_int(sqlite3_stmt *pStmt, int iCol);
double sqlite3_column_double(sqlite3_stmt *pStmt, int iCol);
const char *sqlite3_column_text(sqlite3_stmt *pStmt, int iCol);
int sqlite3_column_bytes(sqlite3_stmt *pStmt, int iCol);

/* Error Handling & Diagnostics */
const char *sqlite3_errmsg(sqlite3 *pDb);
int sqlite3_errcode(sqlite3 *pDb);
int sqlite3_changes(sqlite3 *pDb);
int sqlite3_total_changes(sqlite3 *pDb);
int64_t sqlite3_last_insert_rowid(sqlite3 *pDb);

/* Direct One-Shot Execution */
int sqlite3_exec(
    sqlite3 *pDb,
    const char *sql,
    int (*callback)(void*,int,char**,char**),
    void *arg,
    char **errmsg
);

/* Extension Loading and User-Defined Function Hooks */
int sqlite3_load_extension(
    sqlite3 *pDb,
    const char *zFile,
    const char *zProc,
    char **pzErrMsg
);

typedef struct sqlite3_context sqlite3_context;
typedef struct sqlite3_value sqlite3_value;

typedef void (*sqlite3_scalar_func_callback)(
    sqlite3_context *context,
    int argc,
    sqlite3_value **argv
);

int sqlite3_create_function(
    sqlite3 *pDb,
    const char *zFunctionName,
    int nArg,
    int eTextRep,
    void *pApp,
    sqlite3_scalar_func_callback xFunc,
    void (*xStep)(sqlite3_context*,int,sqlite3_value**),
    void (*xFinal)(sqlite3_context*)
);

/* Virtual Table Structs and Module Registration */
typedef struct sqlite3_vtab sqlite3_vtab;
typedef struct sqlite3_vtab_cursor sqlite3_vtab_cursor;
typedef struct sqlite3_index_info sqlite3_index_info;

struct sqlite3_vtab {
    const struct sqlite3_module *pModule;
    int nRef;
    char *zErrMsg;
};

struct sqlite3_vtab_cursor {
    sqlite3_vtab *pVtab;
};

typedef struct sqlite3_module {
    int iVersion;
    int (*xCreate)(sqlite3 *pDb, void *pAux, int argc, const char *const *argv, sqlite3_vtab **ppVTab, char **pzErr);
    int (*xConnect)(sqlite3 *pDb, void *pAux, int argc, const char *const *argv, sqlite3_vtab **ppVTab, char **pzErr);
    int (*xBestIndex)(sqlite3_vtab *pVTab, sqlite3_index_info *pIndexInfo);
    int (*xDisconnect)(sqlite3_vtab *pVTab);
    int (*xDestroy)(sqlite3_vtab *pVTab);
    int (*xOpen)(sqlite3_vtab *pVTab, sqlite3_vtab_cursor **ppCursor);
    int (*xClose)(sqlite3_vtab_cursor *pCursor);
    int (*xFilter)(sqlite3_vtab_cursor *pCursor, int idxNum, const char *idxStr, int argc, sqlite3_value **argv);
    int (*xNext)(sqlite3_vtab_cursor *pCursor);
    int (*xEof)(sqlite3_vtab_cursor *pCursor);
    int (*xColumn)(sqlite3_vtab_cursor *pCursor, sqlite3_context *pContext, int N);
    int (*xRowid)(sqlite3_vtab_cursor *pCursor, int64_t *pRowid);
    int (*xUpdate)(sqlite3_vtab *pVTab, int argc, sqlite3_value **argv, int64_t *pRowid);
} sqlite3_module;

int sqlite3_create_module(
    sqlite3 *pDb,
    const char *zName,
    const sqlite3_module *pModule,
    void *pClientData
);

#ifdef __cplusplus
}
#endif

#endif /* LEANSQL_H */
