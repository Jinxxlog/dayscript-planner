// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weekly_todo.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WeeklyTodoAdapter extends TypeAdapter<WeeklyTodo> {
  @override
  final int typeId = 1;

  @override
  WeeklyTodo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WeeklyTodo(
      id: fields[0] as String,
      title: fields[1] as String,
      days: (fields[2] as List).cast<int>(),
      isCompleted: fields[3] as bool,
      startTime: fields[4] as DateTime?,
      endTime: fields[5] as DateTime?,
      textTime: fields[6] as String?,
      color: fields[7] as String,
    );
  }

  @override
  void write(BinaryWriter writer, WeeklyTodo obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.days)
      ..writeByte(3)
      ..write(obj.isCompleted)
      ..writeByte(4)
      ..write(obj.startTime)
      ..writeByte(5)
      ..write(obj.endTime)
      ..writeByte(6)
      ..write(obj.textTime)
      ..writeByte(7)
      ..write(obj.color);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeeklyTodoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
