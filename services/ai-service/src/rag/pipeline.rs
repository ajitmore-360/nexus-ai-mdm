use anyhow::Result;
use tracing::instrument;
use uuid::Uuid;

use crate::embeddings::Encoder;
use crate::llm::{OllamaClient, Prompts};
use crate::rag::retriever::{RagRetriever, RetrievedDoc};

/// Full RAG pipeline: embed query → retrieve docs → augment prompt → generate.
pub struct RagPipeline {
    encoder:   Encoder,
    retriever: RagRetriever,
    llm:       OllamaClient,
}

impl RagPipeline {
    pub fn new(encoder: Encoder, retriever: RagRetriever, llm: OllamaClient) -> Self {
        Self { encoder, retriever, llm }
    }

    /// Answer a user question grounded in the tenant's knowledge base.
    ///
    /// Pipeline:
    /// 1. Embed the user question.
    /// 2. Retrieve top-k relevant documents using ANN search.
    /// 3. Build an augmented prompt with retrieved context.
    /// 4. Generate a grounded answer via Llama.
    #[instrument(skip(self, question), fields(tenant_id=%tenant_id))]
    pub async fn answer(
        &self,
        tenant_id:   Uuid,
        tenant_name: &str,
        question:    &str,
        doc_type:    Option<&str>,
    ) -> Result<RagAnswer> {
        // 1. Embed query
        let query_embedding = self.encoder.encode(question).await?;

        // 2. Retrieve relevant docs
        let docs = self
            .retriever
            .retrieve(tenant_id, &query_embedding, doc_type)
            .await?;

        // 3. Build augmented prompt
        let context  = RagRetriever::format_context(&docs);
        let prompt   = Prompts::copilot_rag(question, &context, tenant_name);

        // 4. Generate
        let answer = self.llm.generate(&prompt).await?;

        Ok(RagAnswer {
            answer,
            source_docs: docs,
            question: question.to_string(),
        })
    }

    /// Index a document (plain text) into the knowledge base.
    pub async fn index(
        &self,
        tenant_id: Uuid,
        doc_type:  &str,
        title:     &str,
        content:   &str,
    ) -> Result<Uuid> {
        let embedding = self.encoder.encode(content).await?;
        self.retriever
            .index_document(tenant_id, doc_type, title, content, &embedding)
            .await
    }
}

/// The result of a RAG-grounded answer.
#[derive(Debug)]
#[allow(dead_code)]
pub struct RagAnswer {
    pub answer:      String,
    pub source_docs: Vec<RetrievedDoc>,
    pub question:    String,
}
