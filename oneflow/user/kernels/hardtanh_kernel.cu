/*
Copyright 2020 The OneFlow Authors. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
#include "oneflow/core/framework/framework.h"
#include "oneflow/core/common/data_type.h"
#include "oneflow/core/kernel/util/cuda_half_util.h"
#include "oneflow/core/cuda/elementwise.cuh"
namespace oneflow {

namespace user_op {

template<typename T>
struct HardtanhFunctor {
  __host__ __device__ explicit HardtanhFunctor(T min_val, T max_val)
      : min_val(min_val), max_val(max_val) {}
  __device__ T operator()(T x) const {
    if (x <= min_val)
      return min_val;
    else if (x >= max_val)
      return max_val;
    else
      return x;
  }
  T min_val;
  T max_val;
};

template<typename T>
struct HardtanhGradFunctor {
  __host__ __device__ explicit HardtanhGradFunctor(T min_val, T max_val)
      : min_val(min_val), max_val(max_val) {}
  __device__ T operator()(T x, T dy) const {
    return (x > min_val && x < max_val) ? dy : static_cast<T>(0);
  }
  T min_val;
  T max_val;
};

template<DeviceType device_type, typename T>
class GpuHardtanhKernel final : public OpKernel {
 public:
  GpuHardtanhKernel() = default;
  ~GpuHardtanhKernel() = default;

 private:
  void Compute(KernelComputeContext* ctx) const override {
    const Tensor* in_tensor = ctx->Tensor4ArgNameAndIndex("in", 0);
    Tensor* out_tensor = ctx->Tensor4ArgNameAndIndex("out", 0);
    const T* in_ptr = in_tensor->dptr<T>();
    T* out_ptr = out_tensor->mut_dptr<T>();
    const T min_val = static_cast<T>(ctx->Attr<double>("min_val"));
    const T max_val = static_cast<T>(ctx->Attr<double>("max_val"));

    const int32_t elem_cnt = in_tensor->shape().elem_cnt();
    OF_CUDA_CHECK(
        (oneflow::cuda::elementwise::Unary(HardtanhFunctor<T>(min_val, max_val), elem_cnt, out_ptr,
                                           in_ptr, ctx->device_ctx()->cuda_stream())));
  }
  bool AlwaysComputeWhenAllOutputsEmpty() const override { return false; }
};

#define REGISTER_GPU_HARDTANH_KERNEL(device, dtype)                                       \
  REGISTER_USER_KERNEL("hardtanh")                                                        \
      .SetCreateFn<GpuHardtanhKernel<device, dtype>>()                                    \
      .SetIsMatchedHob((HobDeviceTag() == device)                                         \
                       & (HobDataType("out", 0) == GetDataType<dtype>::value))            \
      .SetInplaceProposalFn(                                                              \
          [](const InferContext&, AddInplaceArgPair AddInplaceArgPairFn) -> Maybe<void> { \
            OF_RETURN_IF_ERROR(AddInplaceArgPairFn("out", 0, "in", 0, true));             \
            return Maybe<void>::Ok();                                                     \
          });

REGISTER_GPU_HARDTANH_KERNEL(DeviceType::kGPU, half)
REGISTER_GPU_HARDTANH_KERNEL(DeviceType::kGPU, float)
REGISTER_GPU_HARDTANH_KERNEL(DeviceType::kGPU, double)

template<DeviceType device_type, typename T>
class GpuHardtanhGradKernel final : public OpKernel {
 public:
  GpuHardtanhGradKernel() = default;
  ~GpuHardtanhGradKernel() = default;

 private:
  void Compute(KernelComputeContext* ctx) const override {
    const Tensor* y_tensor = ctx->Tensor4ArgNameAndIndex("y", 0);
    const Tensor* dy_tensor = ctx->Tensor4ArgNameAndIndex("dy", 0);
    Tensor* dx_tensor = ctx->Tensor4ArgNameAndIndex("dx", 0);
    const T* y_ptr = y_tensor->dptr<T>();
    const T* dy_ptr = dy_tensor->dptr<T>();
    T* dx_ptr = dx_tensor->mut_dptr<T>();

    const T min_val = static_cast<T>(ctx->Attr<double>("min_val"));
    const T max_val = static_cast<T>(ctx->Attr<double>("max_val"));
    const int32_t elem_cnt = y_tensor->shape().elem_cnt();
    OF_CUDA_CHECK((oneflow::cuda::elementwise::Binary(HardtanhGradFunctor<T>(min_val, max_val),
                                                      elem_cnt, dx_ptr, y_ptr, dy_ptr,
                                                      ctx->device_ctx()->cuda_stream())));
  }
  bool AlwaysComputeWhenAllOutputsEmpty() const override { return false; }
};

#define REGISTER_GPU_HARDTANH_BACKWARD_KERNEL(device, dtype)                              \
  REGISTER_USER_KERNEL("hardtanh_grad")                                                   \
      .SetCreateFn<GpuHardtanhGradKernel<device, dtype>>()                                \
      .SetIsMatchedHob((HobDeviceTag() == device)                                         \
                       & (HobDataType("dx", 0) == GetDataType<dtype>::value))             \
      .SetInplaceProposalFn(                                                              \
          [](const InferContext&, AddInplaceArgPair AddInplaceArgPairFn) -> Maybe<void> { \
            OF_RETURN_IF_ERROR(AddInplaceArgPairFn("dx", 0, "dy", 0, true));              \
            return Maybe<void>::Ok();                                                     \
          });

REGISTER_GPU_HARDTANH_BACKWARD_KERNEL(DeviceType::kGPU, half)
REGISTER_GPU_HARDTANH_BACKWARD_KERNEL(DeviceType::kGPU, float)
REGISTER_GPU_HARDTANH_BACKWARD_KERNEL(DeviceType::kGPU, double)

}  // namespace user_op

}  // namespace oneflow