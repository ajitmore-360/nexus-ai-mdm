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
        tenant_id:    Uuid,
        tenant_name:  &str,
        question:     &str,
        doc_type:     Option<&str>,
        role:         &str,
        entity_types: &[String],
        fmt:          &str,
    ) -> Result<RagAnswer> {
        // 1. Embed query + fetch live stats in parallel (scoped for stewards)
        let scoped_types: Option<&[String]> = if role == "steward" && !entity_types.is_empty() {
            Some(entity_types)
        } else {
            None
        };
        let (query_embedding, live_stats) = tokio::join!(
            self.encoder.encode(question),
            self.retriever.fetch_live_stats_scoped(tenant_id, scoped_types),
        );
        let query_embedding = query_embedding?;

        // 2. Retrieve relevant docs
        let docs = self
            .retriever
            .retrieve(tenant_id, &query_embedding, doc_type)
            .await?;

        // 3. Build augmented prompt (RAG context + live counts + role context)
        let context = self.retriever.format_context(&docs);
        let prompt  = Prompts::copilot_rag(question, &context, tenant_name, &live_stats, role, entity_types, fmt);

        // 4. Generate (JSON mode when table format is expected)
        let answer = self.llm.generate(&prompt, fmt == "table").await?;

        Ok(RagAnswer {
            answer,
            source_docs: docs,
            question: question.to_string(),
        })
    }

    /// Build the RAG-augmented prompt without calling the LLM.
    ///
    /// Runs the embed → retrieve → format steps and returns the final prompt
    /// string.  The streaming handler calls this first, then passes the prompt
    /// to `OllamaClient::generate_stream()` directly.
    pub async fn build_prompt(
        &self,
        tenant_id:    Uuid,
        tenant_name:  &str,
        question:     &str,
        doc_type:     Option<&str>,
        role:         &str,
        entity_types: &[String],
        fmt:          &str,
    ) -> Result<String> {
        let scoped_types: Option<&[String]> = if role == "steward" && !entity_types.is_empty() {
            Some(entity_types)
        } else {
            None
        };
        let (query_embedding, live_stats) = tokio::join!(
            self.encoder.encode(question),
            self.retriever.fetch_live_stats_scoped(tenant_id, scoped_types),
        );
        let query_embedding = query_embedding?;
        let docs    = self.retriever.retrieve(tenant_id, &query_embedding, doc_type).await?;
        let context = self.retriever.format_context(&docs);
        Ok(Prompts::copilot_rag(question, &context, tenant_name, &live_stats, role, entity_types, fmt))
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
