# Chinese conversion dictionaries

- Source: `com.github.liuyueyi.quick-chinese-transfer:quick-transfer-core:0.2.17`
- Upstream tag: `0.2.17` (`810e881ce722e7919ad00f283551e897bf7aad77`)
- Files copied verbatim: `tc/t2s.txt`, `tc/s2t.txt`
- Runtime conversion: longest-prefix trie, matching upstream `BasicDictionary.convert`.
- `t2s` additionally applies legado `ChineseUtils.fixT2sDict()` exclusion phrases.
