package com.orbix.pixora.data.db;

import android.database.Cursor;
import android.os.CancellationSignal;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.room.CoroutinesRoom;
import androidx.room.EntityInsertionAdapter;
import androidx.room.RoomDatabase;
import androidx.room.RoomSQLiteQuery;
import androidx.room.util.CursorUtil;
import androidx.room.util.DBUtil;
import androidx.sqlite.db.SupportSQLiteStatement;
import java.lang.Class;
import java.lang.Exception;
import java.lang.Object;
import java.lang.Override;
import java.lang.String;
import java.lang.SuppressWarnings;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.Callable;
import javax.annotation.processing.Generated;
import kotlin.Unit;
import kotlin.coroutines.Continuation;
import kotlinx.coroutines.flow.Flow;

@Generated("androidx.room.RoomProcessor")
@SuppressWarnings({"unchecked", "deprecation"})
public final class CreditDao_Impl implements CreditDao {
  private final RoomDatabase __db;

  private final EntityInsertionAdapter<CreditEntity> __insertionAdapterOfCreditEntity;

  public CreditDao_Impl(@NonNull final RoomDatabase __db) {
    this.__db = __db;
    this.__insertionAdapterOfCreditEntity = new EntityInsertionAdapter<CreditEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "INSERT OR REPLACE INTO `credits` (`id`,`balance`,`totalEarned`,`totalSpent`,`updatedAt`) VALUES (?,?,?,?,?)";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final CreditEntity entity) {
        statement.bindLong(1, entity.getId());
        statement.bindLong(2, entity.getBalance());
        statement.bindLong(3, entity.getTotalEarned());
        statement.bindLong(4, entity.getTotalSpent());
        statement.bindLong(5, entity.getUpdatedAt());
      }
    };
  }

  @Override
  public Object upsert(final CreditEntity entity, final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        __db.beginTransaction();
        try {
          __insertionAdapterOfCreditEntity.insert(entity);
          __db.setTransactionSuccessful();
          return Unit.INSTANCE;
        } finally {
          __db.endTransaction();
        }
      }
    }, $completion);
  }

  @Override
  public Flow<CreditEntity> observe() {
    final String _sql = "SELECT * FROM credits WHERE id = 1";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 0);
    return CoroutinesRoom.createFlow(__db, false, new String[] {"credits"}, new Callable<CreditEntity>() {
      @Override
      @Nullable
      public CreditEntity call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfBalance = CursorUtil.getColumnIndexOrThrow(_cursor, "balance");
          final int _cursorIndexOfTotalEarned = CursorUtil.getColumnIndexOrThrow(_cursor, "totalEarned");
          final int _cursorIndexOfTotalSpent = CursorUtil.getColumnIndexOrThrow(_cursor, "totalSpent");
          final int _cursorIndexOfUpdatedAt = CursorUtil.getColumnIndexOrThrow(_cursor, "updatedAt");
          final CreditEntity _result;
          if (_cursor.moveToFirst()) {
            final int _tmpId;
            _tmpId = _cursor.getInt(_cursorIndexOfId);
            final long _tmpBalance;
            _tmpBalance = _cursor.getLong(_cursorIndexOfBalance);
            final long _tmpTotalEarned;
            _tmpTotalEarned = _cursor.getLong(_cursorIndexOfTotalEarned);
            final long _tmpTotalSpent;
            _tmpTotalSpent = _cursor.getLong(_cursorIndexOfTotalSpent);
            final long _tmpUpdatedAt;
            _tmpUpdatedAt = _cursor.getLong(_cursorIndexOfUpdatedAt);
            _result = new CreditEntity(_tmpId,_tmpBalance,_tmpTotalEarned,_tmpTotalSpent,_tmpUpdatedAt);
          } else {
            _result = null;
          }
          return _result;
        } finally {
          _cursor.close();
        }
      }

      @Override
      protected void finalize() {
        _statement.release();
      }
    });
  }

  @Override
  public Object get(final Continuation<? super CreditEntity> $completion) {
    final String _sql = "SELECT * FROM credits WHERE id = 1";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 0);
    final CancellationSignal _cancellationSignal = DBUtil.createCancellationSignal();
    return CoroutinesRoom.execute(__db, false, _cancellationSignal, new Callable<CreditEntity>() {
      @Override
      @Nullable
      public CreditEntity call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfBalance = CursorUtil.getColumnIndexOrThrow(_cursor, "balance");
          final int _cursorIndexOfTotalEarned = CursorUtil.getColumnIndexOrThrow(_cursor, "totalEarned");
          final int _cursorIndexOfTotalSpent = CursorUtil.getColumnIndexOrThrow(_cursor, "totalSpent");
          final int _cursorIndexOfUpdatedAt = CursorUtil.getColumnIndexOrThrow(_cursor, "updatedAt");
          final CreditEntity _result;
          if (_cursor.moveToFirst()) {
            final int _tmpId;
            _tmpId = _cursor.getInt(_cursorIndexOfId);
            final long _tmpBalance;
            _tmpBalance = _cursor.getLong(_cursorIndexOfBalance);
            final long _tmpTotalEarned;
            _tmpTotalEarned = _cursor.getLong(_cursorIndexOfTotalEarned);
            final long _tmpTotalSpent;
            _tmpTotalSpent = _cursor.getLong(_cursorIndexOfTotalSpent);
            final long _tmpUpdatedAt;
            _tmpUpdatedAt = _cursor.getLong(_cursorIndexOfUpdatedAt);
            _result = new CreditEntity(_tmpId,_tmpBalance,_tmpTotalEarned,_tmpTotalSpent,_tmpUpdatedAt);
          } else {
            _result = null;
          }
          return _result;
        } finally {
          _cursor.close();
          _statement.release();
        }
      }
    }, $completion);
  }

  @NonNull
  public static List<Class<?>> getRequiredConverters() {
    return Collections.emptyList();
  }
}
