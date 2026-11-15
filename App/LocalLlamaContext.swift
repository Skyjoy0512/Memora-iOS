import Foundation
import LlamaSwift

// Adapted from Volocal's LlamaContext (MIT). See Resources/Volocal-LICENSE.txt.
actor LocalLlamaContext {
  enum Failure: Error { case load, context, promptTooLong, decode }

  private static let backend: Void = { llama_backend_init() }()
  private var model: OpaquePointer
  private var context: OpaquePointer
  private var vocab: OpaquePointer
  private var sampler: UnsafeMutablePointer<llama_sampler>
  private var batch: llama_batch
  private var position: Int32 = 0

  static func load(path: String) async throws -> LocalLlamaContext {
    try await Task.detached(priority: .userInitiated) {
      _ = backend
      var parameters = llama_model_default_params()
      #if targetEnvironment(simulator)
      parameters.n_gpu_layers = 0
      #else
      parameters.n_gpu_layers = 99
      #endif
      guard let model = llama_model_load_from_file(path, parameters) else { throw Failure.load }
      var options = llama_context_default_params()
      options.n_ctx = 2_048
      options.n_batch = 256
      options.n_threads = Int32(max(1, min(6, ProcessInfo.processInfo.processorCount - 2)))
      options.n_threads_batch = options.n_threads
      guard let context = llama_init_from_model(model, options), let vocab = llama_model_get_vocab(model) else {
        llama_model_free(model)
        throw Failure.context
      }
      return LocalLlamaContext(model: model, context: context, vocab: vocab)
    }.value
  }

  private init(model: OpaquePointer, context: OpaquePointer, vocab: OpaquePointer) {
    self.model = model
    self.context = context
    self.vocab = vocab
    batch = llama_batch_init(256, 0, 1)
    sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())!
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(20))
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95, 1))
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7))
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED))
  }

  isolated deinit {
    llama_sampler_free(sampler)
    llama_batch_free(batch)
    llama_free(context)
    llama_model_free(model)
  }

  func begin(prompt: String) throws {
    try Task.checkCancellation()
    let bytes = prompt.utf8CString
    let required = bytes.withUnsafeBufferPointer {
      llama_tokenize(vocab, $0.baseAddress, Int32($0.count - 1), nil, 0, true, true)
    }
    guard required < 0 else { throw Failure.decode }
    let count = Int(-required)
    guard count <= 1_536 else { throw Failure.promptTooLong }
    var tokens = [llama_token](repeating: 0, count: count)
    let actual = bytes.withUnsafeBufferPointer {
      llama_tokenize(vocab, $0.baseAddress, Int32($0.count - 1), &tokens, Int32(count), true, true)
    }
    guard actual > 0, actual <= count else { throw Failure.decode }
    if let memory = llama_get_memory(context) { llama_memory_clear(memory, true) }
    llama_sampler_reset(sampler)
    position = 0
    // Native batches have a fixed capacity; never write a long prompt past it.
    for start in stride(from: 0, to: Int(actual), by: 256) {
      try Task.checkCancellation()
      batch.n_tokens = 0
      for index in start..<min(Int(actual), start + 256) {
        add(tokens[index], at: Int32(index), logits: index == Int(actual) - 1)
      }
      guard llama_decode(context, batch) == 0 else { throw Failure.decode }
    }
    position = actual
  }

  func next() throws -> [UInt8]? {
    try Task.checkCancellation()
    guard position < 2_047 else { return nil }
    let token = llama_sampler_sample(sampler, context, -1)
    if llama_vocab_is_eog(vocab, token) { return nil }
    var bytes = [CChar](repeating: 0, count: 128)
    var length = llama_token_to_piece(vocab, token, &bytes, Int32(bytes.count), 0, false)
    if length < 0 {
      guard length >= -4_096 else { throw Failure.decode }
      bytes = [CChar](repeating: 0, count: Int(-length))
      length = llama_token_to_piece(vocab, token, &bytes, Int32(bytes.count), 0, false)
    }
    guard length >= 0, length <= bytes.count else { throw Failure.decode }
    batch.n_tokens = 0
    add(token, at: position, logits: true)
    position += 1
    guard llama_decode(context, batch) == 0 else { throw Failure.decode }
    return bytes.prefix(Int(length)).map { UInt8(bitPattern: $0) }
  }

  private func add(_ token: llama_token, at position: Int32, logits: Bool) {
    let index = Int(batch.n_tokens)
    batch.token[index] = token
    batch.pos[index] = position
    batch.n_seq_id[index] = 1
    batch.seq_id[index]![0] = 0
    batch.logits[index] = logits ? 1 : 0
    batch.n_tokens += 1
  }
}
