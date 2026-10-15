#ifndef QIYOU_DEVICE_STORE_H_
#define QIYOU_DEVICE_STORE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateDeviceStore(flutter::BinaryMessenger* messenger);

#endif
